# Jido Ecosystem GitHub Actions

Reusable GitHub Actions workflows for Elixir CI/CD across the Jido ecosystem repositories.

> **Note**: This repository is temporarily hosted at `agentjido/github-actions`. It will be transferred to `agentjido/github-actions` once permissions are available. Update workflow references accordingly after transfer.

## Workflows

| Workflow | Purpose | Typical Duration |
|----------|---------|------------------|
| `elixir-lint.yml` | Code quality checks (format, compile, credo, dialyzer) | < 5 min |
| `elixir-test.yml` | Test execution with optional PostgreSQL | < 8 min |
| `elixir-release.yml` | Automated releases via git_ops | < 3 min |

## Quick Start

### CI Workflow (Lint + Test)

Create `.github/workflows/ci.yml` in your repository:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  lint:
    name: Lint
    uses: agentjido/github-actions/.github/workflows/elixir-lint.yml@v1

  test:
    name: Test
    uses: agentjido/github-actions/.github/workflows/elixir-test.yml@v1
```

### With PostgreSQL

```yaml
jobs:
  test:
    name: Test
    uses: agentjido/github-actions/.github/workflows/elixir-test.yml@v1
    with:
      postgres: true
```

### Release Workflow

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  workflow_dispatch:

permissions:
  contents: write

jobs:
  release:
    name: Release
    uses: agentjido/github-actions/.github/workflows/elixir-release.yml@v1
    secrets: inherit
```

## Workflow Inputs

### elixir-lint.yml

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `otp_version` | string | - | OTP version (if no .tool-versions) |
| `elixir_version` | string | - | Elixir version (if no .tool-versions) |
| `version_file` | string | `.tool-versions` | Path to version file |
| `mix_env` | string | `test` | MIX_ENV for compilation |
| `lint_command` | string | `mix quality` | Command to run for linting |

### elixir-test.yml

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `otp_version` | string | - | OTP version (if no .tool-versions) |
| `elixir_version` | string | - | Elixir version (if no .tool-versions) |
| `version_file` | string | `.tool-versions` | Path to version file |
| `mix_env` | string | `test` | MIX_ENV for tests |
| `test_command` | string | `mix test` | Command to run tests |
| `postgres` | boolean | `false` | Enable PostgreSQL service |
| `postgres_image` | string | `postgres:16-alpine` | PostgreSQL Docker image |

### elixir-release.yml

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `otp_version` | string | - | OTP version (if no .tool-versions) |
| `elixir_version` | string | - | Elixir version (if no .tool-versions) |
| `version_file` | string | `.tool-versions` | Path to version file |
| `mix_env` | string | `dev` | MIX_ENV for release |
| `release_command` | string | `mix git_ops.release --yes` | Release command |

## Version Pinning

- **`@v1`**: Recommended for most users. Automatically receives compatible updates.
- **`@v1.0.0`**: Pin to exact version for maximum stability.

```yaml
# Recommended: Get compatible updates
uses: agentjido/github-actions/.github/workflows/elixir-lint.yml@v1

# Exact version pinning
uses: agentjido/github-actions/.github/workflows/elixir-lint.yml@v1.0.0
```

## Prerequisites

### For Lint Workflow

Your repository needs a `mix quality` alias in `mix.exs`:

```elixir
defp aliases do
  [
    quality: [
      "format --check-formatted",
      "compile --warnings-as-errors",
      "credo --strict",
      "dialyzer"
    ]
  ]
end
```

### For Release Workflow

Your repository needs `git_ops` configured:

```elixir
# mix.exs
defp deps do
  [
    {:git_ops, "~> 2.9", only: :dev, runtime: false}
  ]
end

# config/config.exs
if config_env() != :prod do
  config :git_ops,
    mix_project: Mix.Project.get!(),
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/agentjido/YOUR_REPO",
    manage_mix_version?: true,
    version_tag_prefix: "v"
end
```

## Caching

All workflows implement intelligent caching:

- **Cache key**: `{os}-mix-{job}-{mix.lock hash}-{.tool-versions hash}`
- **Cached paths**: `deps/`, `_build/`, `~/.mix`, `~/.hex`
- **Dialyzer PLT**: Cached separately for lint workflow

Cache misses are logged for debugging.

## Consumer Repositories

This workflow repository serves the following Jido ecosystem repos:

- [jido](https://github.com/agentjido/jido) - Core framework
- [jido_action](https://github.com/agentjido/jido_action) - Action system
- [jido_signal](https://github.com/agentjido/jido_signal) - Signal processing
- [jido_workbench](https://github.com/agentjido/jido_workbench) - Development workbench
- [req_llm](https://github.com/agentjido/req_llm) - LLM integration
- [llm_db](https://github.com/agentjido/llm_db) - LLM database

## Contributing

1. Fork this repository
2. Create a feature branch
3. Make changes to workflow files
4. Test in a consumer repository
5. Submit a pull request

## License

MIT License - See [LICENSE](LICENSE) for details.
