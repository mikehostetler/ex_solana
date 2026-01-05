# Fly.io Elixir Development Sandbox
# Elixir 1.19 + OTP 28 with code-server IDE

FROM elixir:1.19-otp-28

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    wget \
    unzip \
    openssh-client \
    inotify-tools \
    postgresql-client \
    ca-certificates \
    gnupg \
    locales \
    sudo \
    htop \
    vim \
    ripgrep \
    fd-find \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Set up locales
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Install code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Install flyctl
RUN curl -L https://fly.io/install.sh | sh
ENV FLYCTL_INSTALL="/root/.fly"
ENV PATH="${FLYCTL_INSTALL}/bin:${PATH}"

# Install Hex and Rebar globally
RUN mix local.hex --force && \
    mix local.rebar --force

# Install common Elixir tools
RUN mix archive.install hex phx_new --force

# Install code-server extensions
RUN code-server --install-extension elixir-lsp.elixir-ls && \
    code-server --install-extension bradlc.vscode-tailwindcss && \
    code-server --install-extension eamodio.gitlens && \
    code-server --install-extension esbenp.prettier-vscode && \
    code-server --install-extension pkief.material-icon-theme

# Set shell
ENV SHELL=/bin/bash

# Working directory for projects
WORKDIR /workspace

# Copy configuration files
COPY settings.json /root/.local/share/code-server/User/settings.json
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Environment variables
ENV CODE_SERVER_PORT=9090

ENTRYPOINT ["/entrypoint.sh"]
