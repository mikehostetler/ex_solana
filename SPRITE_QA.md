# Sprite Commands QA Testing Plan

## Prerequisites

- `SPRITE_TOKEN` set in `.env` or environment
- `ANTHROPIC_API_KEY` set for Claude tests
- SSH key with GitHub access (deploy key or personal)
- Private repo access configured

## Test Matrix

### 1. Basic Lifecycle

```bash
# List sprites (should work with empty list)
mix sprite.list

# Create bare sprite
mix sprite.create test-bare --no-repo --no-checkpoint

# Verify it appears
mix sprite.list

# Check status
mix sprite.status test-bare

# Destroy
mix sprite.destroy test-bare --force
```

### 2. Full Dev Environment Setup

```bash
# Create with repo clone (public repo, no SSH needed)
mix sprite.create test-public \
  --repo https://github.com/agentjido/jido.git \
  --branch main \
  --no-checkpoint

# Verify status shows git info
mix sprite.status test-public

# Run a command
mix sprite.exec test-public -- ls -la

# Cleanup
mix sprite.destroy test-public --force
```

### 3. Private Repo with SSH Key

```bash
# Create with SSH key for private repo
mix sprite.create test-private \
  --repo git@github.com:agentjido/jido_workspace.git \
  --branch main \
  --ssh-key ~/.ssh/id_ed25519

# Verify clone worked
mix sprite.exec test-private -- git remote -v

# Cleanup
mix sprite.destroy test-private --force
```

### 4. Claude CLI Integration

```bash
# Create with Claude configured
mix sprite.create test-claude \
  --no-repo \
  --claude-key $ANTHROPIC_API_KEY

# Verify Claude CLI works
mix sprite.exec test-claude -- bash -lc "source ~/.config/claude/env.sh && claude --version"

# Test with --test-claude flag (runs hello world prompt)
mix sprite.create test-claude-prompt \
  --no-repo \
  --claude-key $ANTHROPIC_API_KEY \
  --test-claude

# Cleanup
mix sprite.destroy test-claude --force
mix sprite.destroy test-claude-prompt --force
```

### 5. Checkpoint Operations

```bash
# Create sprite
mix sprite.create test-checkpoint --no-repo

# Create a file
mix sprite.exec test-checkpoint -- touch /home/sprite/testfile.txt

# Create checkpoint
mix sprite.checkpoint test-checkpoint --comment "after creating testfile"

# List checkpoints
mix sprite.checkpoints test-checkpoint

# Delete the file
mix sprite.exec test-checkpoint -- rm /home/sprite/testfile.txt

# Verify deleted
mix sprite.exec test-checkpoint -- ls /home/sprite/

# Restore checkpoint
mix sprite.restore test-checkpoint v1

# Verify file is back
mix sprite.exec test-checkpoint -- ls /home/sprite/

# Cleanup
mix sprite.destroy test-checkpoint --force
```

### 6. Git Workflow

```bash
# Create with repo
mix sprite.create test-git \
  --repo git@github.com:YOUR_TEST_REPO.git \
  --branch test-sprite-changes \
  --ssh-key ~/.ssh/id_ed25519

# Check git status
mix sprite.git.status test-git

# Make a change
mix sprite.exec test-git -- bash -c "echo 'test' >> README.md"

# Check status again (should show modified)
mix sprite.git.status test-git

# Push changes
mix sprite.git.push test-git --message "Test commit from sprite"

# Verify on GitHub that commit appeared

# Cleanup
mix sprite.destroy test-git --force
```

## Expected Behaviors

| Command | Success Indicator |
|---------|-------------------|
| `sprite.list` | Shows sprites or "No sprites found" |
| `sprite.create` | Prints "[ok] Sprite created" and URL |
| `sprite.destroy` | Prints "[ok] Sprite destroyed" |
| `sprite.status` | Shows URL, git branch, git status |
| `sprite.exec` | Command output streams to terminal |
| `sprite.checkpoint` | Prints "[ok] Checkpoint created" |
| `sprite.checkpoints` | Lists checkpoint IDs with comments |
| `sprite.restore` | Prints "[ok] Checkpoint restored" |
| `sprite.git.status` | Shows branch and git status output |
| `sprite.git.push` | Commits and pushes, shows pull command |

## Error Cases to Verify

- [ ] `sprite.create` without name shows usage
- [ ] `sprite.destroy` without `--force` prompts for confirmation
- [ ] Missing `SPRITE_TOKEN` raises clear error
- [ ] Invalid SSH key path raises error before API call
- [ ] `sprite.status` on non-existent sprite shows "not found"
- [ ] `sprite.restore` with bad checkpoint ID shows error

## Environment Variables

| Variable | Purpose | Required |
|----------|---------|----------|
| `SPRITE_TOKEN` | Sprites API auth | Yes |
| `SPRITE_SSH_KEY_PATH` | Default SSH key | No |
| `ANTHROPIC_API_KEY` | Default Claude key | No |
| `SPRITE_DEFAULT_REPO` | Default repo URL | No |
