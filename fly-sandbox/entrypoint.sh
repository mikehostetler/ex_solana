#!/bin/bash
set -e

echo "=========================================="
echo "  Fly.io Elixir Development Sandbox"
ELIXIR_VERSION=$(elixir --version 2>&1) && echo "  $(echo "$ELIXIR_VERSION" | head -1)" || echo "  Elixir (version check failed)"
echo "=========================================="

WORKSPACE_DIR="/workspace"
mkdir -p "$WORKSPACE_DIR"

# Clean up lost+found from volume mount
rm -rf "$WORKSPACE_DIR/lost+found" 2>/dev/null || true

# ========================================
# SSH Key Setup
# ========================================
SSH_DIR="$WORKSPACE_DIR/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

SSH_KEY="$SSH_DIR/id_ed25519"

# Priority: injected key > existing key > generate new
if [ -f "/run/secrets/ssh_key" ]; then
    echo "Using injected SSH key..."
    cp /run/secrets/ssh_key "$SSH_KEY"
    chmod 600 "$SSH_KEY"
    # Generate public key from private
    ssh-keygen -y -f "$SSH_KEY" > "${SSH_KEY}.pub" 2>/dev/null || true
elif [ ! -f "$SSH_KEY" ]; then
    echo "Generating SSH key..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "fly-sandbox@$(hostname)"
    echo ""
    echo "=========================================="
    echo "  NEW SSH PUBLIC KEY (add to GitHub):"
    echo "=========================================="
    cat "${SSH_KEY}.pub"
    echo "=========================================="
    echo ""
else
    echo "Using existing SSH key"
fi

# Configure SSH hosts
cat > "$SSH_DIR/config" << 'EOF'
Host github.com
    HostName github.com
    User git
    IdentityFile /workspace/.ssh/id_ed25519
    StrictHostKeyChecking accept-new

Host gitlab.com
    HostName gitlab.com
    User git
    IdentityFile /workspace/.ssh/id_ed25519
    StrictHostKeyChecking accept-new

Host *
    StrictHostKeyChecking accept-new
EOF
chmod 600 "$SSH_DIR/config"

# Link to root's .ssh
mkdir -p /root/.ssh
ln -sf "$SSH_DIR/config" /root/.ssh/config
ln -sf "$SSH_KEY" /root/.ssh/id_ed25519
[ -f "${SSH_KEY}.pub" ] && ln -sf "${SSH_KEY}.pub" /root/.ssh/id_ed25519.pub

# ========================================
# Git Configuration
# ========================================
[ -n "$GIT_USER_NAME" ] && git config --global user.name "$GIT_USER_NAME"
[ -n "$GIT_USER_EMAIL" ] && git config --global user.email "$GIT_USER_EMAIL"
git config --global init.defaultBranch main
git config --global pull.rebase false

# ========================================
# Coding Agents (pre-installed in image)
# ========================================
export PATH="/root/.local/bin:$PATH"

# Verify agents are available
command -v amp &> /dev/null && echo "Amp CLI: $(amp --version 2>/dev/null || echo 'ready')"
command -v claude &> /dev/null && echo "Claude Code: ready"

# Configure API keys if provided (auth happens at runtime)
[ -n "$AMP_API_KEY" ] && export AMP_API_KEY
[ -n "$ANTHROPIC_API_KEY" ] && export ANTHROPIC_API_KEY

# ========================================
# Repository Checkout (shallow clone for speed)
# ========================================
if [ -n "$GIT_REPO" ]; then
    REPO_NAME=$(basename "$GIT_REPO" .git)
    REPO_DIR="$WORKSPACE_DIR/$REPO_NAME"
    
    if [ ! -d "$REPO_DIR" ]; then
        echo "Cloning repository (shallow): $GIT_REPO"
        if git clone --depth 1 --single-branch "$GIT_REPO" "$REPO_DIR"; then
            echo "Repository cloned!"
            if [ -f "$REPO_DIR/mix.exs" ]; then
                echo "Fetching Elixir dependencies..."
                cd "$REPO_DIR" && mix deps.get
            fi
        else
            echo "Clone failed - check SSH key is added to GitHub"
        fi
    else
        echo "Repository exists at $REPO_DIR"
        cd "$REPO_DIR"
        if [ -n "$BRANCH_NAME" ]; then
            echo "Checking out branch: $BRANCH_NAME"
            git fetch --depth 1 origin "$BRANCH_NAME" 2>/dev/null || true
            git checkout "$BRANCH_NAME" 2>/dev/null || git checkout -b "$BRANCH_NAME" origin/"$BRANCH_NAME" 2>/dev/null || true
        fi
        git pull --ff-only 2>/dev/null || echo "Could not auto-pull"
    fi
fi

# ========================================
# Start code-server
# ========================================
cd "$WORKSPACE_DIR"

echo ""
echo "Starting code-server on port $CODE_SERVER_PORT..."
echo ""

exec code-server \
    --bind-addr "0.0.0.0:$CODE_SERVER_PORT" \
    --auth password \
    --disable-telemetry \
    "$WORKSPACE_DIR"
