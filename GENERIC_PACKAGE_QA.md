# Jido Ecosystem Package Quality Standards

This document defines the quality standards for all public OSS packages in the Jido ecosystem. These patterns are derived from `req_llm`, `llm_db`, `jido_action`, and `jido_signal`.

---

## Package Structure

### Required Files

```
my_package/
├── .github/
│   └── workflows/
│       ├── ci.yml              # Required: Lint + test matrix
│       └── release.yml         # Required: Hex publish workflow
├── config/
│   ├── config.exs              # Base configuration
│   ├── dev.exs                 # Development overrides
│   └── test.exs                # Test overrides
├── guides/                     # Optional: Additional documentation
│   └── getting-started.md
├── lib/
│   └── my_package.ex
├── test/
│   ├── support/                # Test helpers, fixtures
│   └── my_package_test.exs
├── .credo.exs                  # Credo configuration
├── .formatter.exs              # Formatter configuration
├── .gitignore
├── AGENTS.md                   # AI agent instructions
├── CHANGELOG.md                # Conventional changelog
├── CONTRIBUTING.md             # Contribution guidelines
├── LICENSE                     # Apache-2.0 or MIT
├── mix.exs
├── mix.lock
├── README.md
└── usage-rules.md              # LLM usage rules (for Cursor/etc)
```

---

## mix.exs Configuration

### Standard Project Configuration

```elixir
defmodule MyPackage.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/agentjido/my_package"
  @description "Brief description of the package"

  def project do
    [
      app: :my_package,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Documentation
      name: "My Package",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),

      # Test Coverage
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: 90]
      ],

      # Dialyzer
      dialyzer: [
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt"
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Runtime dependencies
      {:jason, "~> 1.4"},
      {:zoi, "~> 0.14"},

      # Dev/Test dependencies
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "git_hooks.install"],
      test: "test --exclude flaky",
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --min-priority higher",
        "dialyzer"
      ]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE", "CHANGELOG.md", "usage-rules.md"],
      maintainers: ["Your Name"],
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "https://hexdocs.pm/my_package/changelog.html",
        "Discord" => "https://agentjido.xyz/discord",
        "Documentation" => "https://hexdocs.pm/my_package",
        "GitHub" => @source_url,
        "Website" => "https://agentjido.xyz"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md"
      ]
    ]
  end
end
```

---

## Quality Checks

### The `mix quality` Alias

All packages MUST define a `quality` alias that runs:

```elixir
quality: [
  "format --check-formatted",      # Code formatting
  "compile --warnings-as-errors",  # No compiler warnings
  "credo --min-priority higher",   # Linting
  "dialyzer"                       # Type checking
]
```

### Running Quality Checks

```bash
# Full quality check
mix quality
# or
mix q

# Individual checks
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --min-priority higher
mix dialyzer
```

---

## Testing Standards

### Coverage Requirements

- **Minimum threshold**: 90% line coverage
- **Tool**: ExCoveralls
- **CI enforcement**: Coverage check in GitHub Actions

### Test Configuration

```elixir
# mix.exs
test_coverage: [
  tool: ExCoveralls,
  summary: [threshold: 90],
  export: "cov",
  ignore_modules: [~r/^MyPackageTest\./]  # Ignore test support modules
]
```

### Running Tests

```bash
# Run tests
mix test

# Run tests with coverage
mix coveralls

# Generate HTML coverage report
mix coveralls.html

# Exclude flaky tests (default behavior)
mix test --exclude flaky

# Include all tests
mix test --include flaky
```

### Test Organization

```
test/
├── support/
│   ├── fixtures.ex         # Test fixtures
│   ├── helpers.ex          # Test helper functions
│   └── case.ex             # Custom ExUnit case modules
├── my_package_test.exs     # High-level API tests
└── my_package/
    ├── module_a_test.exs   # Unit tests for ModuleA
    └── module_b_test.exs   # Unit tests for ModuleB
```

---

## GitHub Actions CI

### Standard CI Workflow

Use the shared workflows from `agentjido/github-actions`:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    name: Lint
    uses: agentjido/github-actions/.github/workflows/elixir-lint.yml@main
    with:
      otp_version: "28"
      elixir_version: "1.19"

  test:
    name: Test
    uses: agentjido/github-actions/.github/workflows/elixir-test.yml@main
    with:
      otp_versions: '["27", "28"]'
      elixir_versions: '["1.18", "1.19"]'
      test_command: mix test
```

### Release Workflow

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    tags:
      - "v*"

jobs:
  publish:
    name: Publish to Hex
    uses: agentjido/github-actions/.github/workflows/elixir-publish.yml@main
    secrets:
      HEX_API_KEY: ${{ secrets.HEX_API_KEY }}
```

---

## Git Hooks & Conventional Commits

### Git Hooks Configuration

```elixir
# config/dev.exs
config :git_hooks,
  auto_install: true,
  verbose: true,
  hooks: [
    commit_msg: [
      tasks: [
        {:cmd, "mix git_ops.check_message"}
      ]
    ],
    pre_commit: [
      tasks: [
        {:mix_task, :format, ["--check-formatted"]}
      ]
    ],
    pre_push: [
      tasks: [
        {:mix_task, :quality}
      ]
    ]
  ]
```

### Conventional Commit Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Types:**

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Formatting, no code change |
| `refactor` | Code change, no fix or feature |
| `perf` | Performance improvement |
| `test` | Adding/fixing tests |
| `chore` | Maintenance, deps, tooling |
| `ci` | CI/CD changes |

**Examples:**

```bash
git commit -m "feat(schema): add validation for email fields"
git commit -m "fix: resolve timeout in async operations"
git commit -m "docs: add getting started guide"
git commit -m "feat!: breaking change to API"
```

---

## Documentation Standards

### Module Documentation

```elixir
defmodule MyPackage.Core do
  @moduledoc """
  Core functionality for MyPackage.

  ## Overview

  Brief description of what this module does.

  ## Examples

      iex> MyPackage.Core.do_thing(:input)
      {:ok, :result}

  ## Configuration

  Describe any configuration options.
  """

  @doc """
  Does a specific thing.

  ## Parameters

    * `input` - Description of input
    * `opts` - Keyword list of options
      * `:timeout` - Timeout in milliseconds (default: 5000)

  ## Returns

    * `{:ok, result}` - On success
    * `{:error, reason}` - On failure

  ## Examples

      iex> do_thing(:foo)
      {:ok, :bar}

  """
  @spec do_thing(atom(), keyword()) :: {:ok, term()} | {:error, term()}
  def do_thing(input, opts \\ [])
end
```

### Required Documentation Files

| File | Purpose |
|------|---------|
| `README.md` | Overview, installation, quick start |
| `CHANGELOG.md` | Version history (conventional changelog) |
| `CONTRIBUTING.md` | How to contribute |
| `AGENTS.md` | AI agent instructions |
| `usage-rules.md` | LLM usage rules |
| `LICENSE` | License text |

---

## Credo Configuration

### Standard .credo.exs

```elixir
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: false,
      parse_timeout: 5000,
      color: true,
      checks: %{
        enabled: [
          {Credo.Check.Consistency.ExceptionNames, []},
          {Credo.Check.Consistency.LineEndings, []},
          {Credo.Check.Consistency.ParameterPatternMatching, []},
          {Credo.Check.Consistency.SpaceAroundOperators, []},
          {Credo.Check.Consistency.SpaceInParentheses, []},
          {Credo.Check.Consistency.TabsOrSpaces, []},
          {Credo.Check.Design.TagTODO, [exit_status: 2]},
          {Credo.Check.Design.TagFIXME, []},
          {Credo.Check.Readability.AliasOrder, []},
          {Credo.Check.Readability.FunctionNames, []},
          {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Readability.ModuleNames, []},
          {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 35]},
          {Credo.Check.Refactor.Nesting, [max_nesting: 5]},
          {Credo.Check.Warning.Dbg, []},
          {Credo.Check.Warning.IoInspect, []},
          {Credo.Check.Warning.IExPry, []}
        ]
      }
    }
  ]
}
```

---

## Formatter Configuration

### Standard .formatter.exs

```elixir
[
  inputs: [
    "{mix,.formatter,.credo}.exs",
    "{config,lib,test}/**/*.{ex,exs}"
  ],
  line_length: 120,
  import_deps: [:typed_struct]
]
```

---

## Dependencies

### Standard Dev/Test Dependencies

```elixir
defp deps do
  [
    # Linting & Static Analysis
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

    # Documentation
    {:ex_doc, "~> 0.31", only: :dev, runtime: false},

    # Test Coverage
    {:excoveralls, "~> 0.18", only: [:dev, :test]},

    # Git Tooling
    {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
    {:git_ops, "~> 2.9", only: :dev, runtime: false},

    # Optional but recommended
    {:quokka, "~> 2.10", only: [:dev, :test], runtime: false},  # Advanced formatting
    {:stream_data, "~> 1.0", only: [:dev, :test]},              # Property testing
    {:mimic, "~> 2.0", only: :test}                             # Mocking
  ]
end
```

### Common Runtime Dependencies

```elixir
# Validation
{:zoi, "~> 0.14"}              # Schema validation
{:nimble_options, "~> 1.1"}    # Option parsing

# JSON
{:jason, "~> 1.4"}

# Structs
{:typedstruct, "~> 0.5"}       # TypedStruct
{:typed_struct, "~> 0.3"}      # Older projects

# Error Handling
{:splode, "~> 0.2"}

# Utilities
{:uniq, "~> 0.6"}              # UUID generation
```

---

## Checklist for New Packages

### Before First Commit

- [ ] `mix.exs` follows standard configuration
- [ ] `quality` alias defined
- [ ] `.formatter.exs` configured
- [ ] `.credo.exs` configured
- [ ] `.gitignore` includes `_build/`, `deps/`, `cover/`, `priv/plts/`, `*.plt`
- [ ] `README.md` with installation and quick start
- [ ] `LICENSE` file present
- [ ] `AGENTS.md` for AI agent instructions

### Before First Release

- [ ] `mix quality` passes
- [ ] `mix test` passes with >90% coverage
- [ ] `mix docs` builds without errors
- [ ] `CHANGELOG.md` has initial entry
- [ ] `CONTRIBUTING.md` describes workflow
- [ ] GitHub Actions CI configured
- [ ] Release workflow configured
- [ ] Hex.pm package metadata complete

### Ongoing Maintenance

- [ ] All PRs pass CI
- [ ] Coverage maintained above threshold
- [ ] Conventional commits enforced
- [ ] CHANGELOG updated on releases
- [ ] Dependencies kept up to date
- [ ] Security advisories addressed promptly

---

## Quick Reference

```bash
# Setup new dev environment
mix setup

# Run all quality checks
mix quality

# Run tests with coverage
mix coveralls.html

# Generate docs
mix docs

# Check commit message format
mix git_ops.check_message

# Create a release
mix git_ops.release
git push && git push --tags
```
