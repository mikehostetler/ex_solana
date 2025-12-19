# Phase 1: Project Foundation and Core Infrastructure

This phase establishes the Elixir project structure, dependency management, and core OTP supervision tree. The foundation must support fault-tolerant operation with proper process isolation, enabling the TUI, agents, and infrastructure services to operate independently while communicating through Phoenix PubSub.

## 1.1 Project Initialization

The project initialization creates the standard Elixir application structure with proper configuration for all required dependencies. The project name `jido_code` reflects its purpose as a coding assistant built on the Jido framework.

### 1.1.1 Create Elixir Project Structure
- [x] **Task 1.1.1 Complete**

Generate the base Elixir application with supervision tree support and configure mix.exs with all required dependencies.

- [x] 1.1.1.1 Run `mix new jido_code --sup` to create supervised application
- [x] 1.1.1.2 Configure mix.exs with dependencies: jido (~> 1.2), jido_ai (local), term_ui (local), phoenix_pubsub (~> 2.1), jason, luerl, rdf (~> 2.0), libgraph (~> 0.16)
- [x] 1.1.1.3 Add development dependencies: ex_doc, credo, dialyxir
- [x] 1.1.1.4 Create config/config.exs with base configuration structure
- [x] 1.1.1.5 Create config/runtime.exs for environment-specific LLM configuration
- [x] 1.1.1.6 Run `mix deps.get` and verify all dependencies compile (success: `mix compile` exits 0)

### 1.1.2 Configure LLM Provider Settings
- [x] **Task 1.1.2 Complete**

Establish the configuration schema for LLM providers using JidoAI's Keyring and Model systems. JidoAI supports 50+ providers through ReqLLM integration - any provider returned by `Jido.AI.Provider.providers/0` is valid.

- [x] 1.1.2.1 Define `:jido_code, :llm` configuration key with provider, model, temperature, max_tokens options
- [x] 1.1.2.2 Create `JidoCode.Config` module to read and validate LLM configuration
- [x] 1.1.2.3 Implement `Config.get_llm_config/0` returning validated `{:ok, config}` or `{:error, reason}`
- [x] 1.1.2.4 Validate provider exists via `Jido.AI.Provider.providers/0` (supports 50+ providers via ReqLLM)
- [x] 1.1.2.5 Support environment variable overrides: `JIDO_CODE_PROVIDER`, `JIDO_CODE_MODEL`, provider-specific API key env vars
- [x] 1.1.2.6 Add runtime validation that API key exists for configured provider via Keyring
- [x] 1.1.2.7 Require explicit provider configuration (no default) - error on startup if not configured
- [x] 1.1.2.8 Write config tests verifying provider switching and validation (success: 13 tests pass)

## 1.2 OTP Supervision Tree

The supervision tree implements fault isolation between infrastructure services, agents, and the TUI layer. Using `:one_for_one` strategy at the top level ensures that a crash in one subsystem doesn't cascade.

### 1.2.1 Application Supervisor Structure
- [x] **Task 1.2.1 Complete**

Implement the main application supervisor with proper child ordering and restart strategies.

- [x] 1.2.1.1 Create `JidoCode.Application` module with `start/2` callback (existed from 1.1.1)
- [x] 1.2.1.2 Add Phoenix.PubSub as first child: `{Phoenix.PubSub, name: JidoCode.PubSub}` (existed from 1.1.1)
- [x] 1.2.1.3 Add Registry for agent lookup: `{Registry, keys: :unique, name: JidoCode.AgentRegistry}` (existed from 1.1.1)
- [x] 1.2.1.4 Add `JidoCode.AgentSupervisor` as DynamicSupervisor for agent processes
- [x] 1.2.1.5 Configure top-level supervisor with `strategy: :one_for_one`
- [x] 1.2.1.6 Verify supervision tree starts correctly via `mix run --no-halt` (success: runs 5+ seconds without errors)

### 1.2.2 Agent Supervisor Implementation
- [x] **Task 1.2.2 Complete**

Create the agent supervisor that manages LLM agent lifecycle with proper restart policies.

- [x] 1.2.2.1 Create `JidoCode.AgentSupervisor` as DynamicSupervisor
- [x] 1.2.2.2 Implement `start_agent/1` to spawn supervised agent processes
- [x] 1.2.2.3 Implement `stop_agent/1` for graceful agent termination
- [x] 1.2.2.4 Configure agent restart strategy: `restart: :transient` (restart on abnormal exit only)
- [x] 1.2.2.5 Add agent process registration via AgentRegistry
- [x] 1.2.2.6 Write tests for agent start/stop/restart behavior (success: agent recovers from crash)

## 1.3 Settings File System

A two-level JSON configuration system that persists user preferences across sessions. Global settings in `~/.jido_code/settings.json` apply to all projects, while local settings in `./jido_code/settings.json` override global values for project-specific configuration.

### 1.3.1 Settings File Structure
- [x] **Task 1.3.1 Complete**

Define the JSON schema and file locations for persistent settings.

- [x] 1.3.1.1 Create `JidoCode.Settings` module for settings management
- [x] 1.3.1.2 Define global settings path: `~/.jido_code/settings.json`
- [x] 1.3.1.3 Define local settings path: `./jido_code/settings.json` (project root)
- [x] 1.3.1.4 Define settings JSON schema:
  ```json
  {
    "provider": "anthropic",
    "model": "claude-3-5-sonnet",
    "providers": ["anthropic", "openai", "openrouter"],
    "models": {
      "anthropic": ["claude-3-5-sonnet", "claude-3-opus"],
      "openai": ["gpt-4o", "gpt-4-turbo"]
    }
  }
  ```
- [x] 1.3.1.5 Create directory `~/.jido_code/` on first write if not exists
- [x] 1.3.1.6 Create directory `./jido_code/` on first write if not exists
- [x] 1.3.1.7 Write schema validation tests (success: valid JSON parses, invalid rejects)

### 1.3.2 Settings Loading and Merging
- [x] **Task 1.3.2 Complete**

Implement loading, merging, and accessing settings with local override priority.

- [x] 1.3.2.1 Implement `Settings.load/0` to read and merge global + local settings
- [x] 1.3.2.2 Load global settings first, then overlay local settings (local wins on conflict)
- [x] 1.3.2.3 Handle missing files gracefully (return empty map for missing file)
- [x] 1.3.2.4 Handle malformed JSON with error logging and fallback to defaults
- [x] 1.3.2.5 Implement `Settings.get/1` and `Settings.get/2` for accessing values with defaults
- [x] 1.3.2.6 Cache loaded settings in memory to avoid repeated file reads
- [x] 1.3.2.7 Write merge tests verifying local overrides global (success: correct precedence)

### 1.3.3 Settings Persistence
- [x] **Task 1.3.3 Complete**

Implement saving settings updates to the appropriate file.

- [x] 1.3.3.1 Implement `Settings.save/2` accepting scope (`:global` or `:local`) and settings map
- [x] 1.3.3.2 Implement `Settings.set/3` for updating individual keys with scope
- [x] 1.3.3.3 Auto-save provider and model to local settings on `/model` command (API ready, TUI integration in Phase 4)
- [x] 1.3.3.4 Implement `Settings.add_provider/2` to add provider to allowed providers list
- [x] 1.3.3.5 Implement `Settings.add_model/3` to add model to provider's model list
- [x] 1.3.3.6 Write atomic file writes (write to temp, then rename) to prevent corruption
- [x] 1.3.3.7 Invalidate memory cache on save
- [x] 1.3.3.8 Write persistence tests verifying round-trip save/load (success: data survives restart)

### 1.3.4 Provider and Model Lists
- [x] **Task 1.3.4 Complete**

Use settings file lists to filter available providers and models in pick-list UI.

- [x] 1.3.4.1 Implement `Settings.get_providers/0` returning providers list from settings
- [x] 1.3.4.2 If `providers` list exists in settings, use it for `/providers` pick-list
- [x] 1.3.4.3 If `providers` list is empty/missing, fall back to `Jido.AI.Provider.providers/0`
- [x] 1.3.4.4 Implement `Settings.get_models/1` returning models list for a provider
- [x] 1.3.4.5 If `models[provider]` exists in settings, use it for `/models` pick-list
- [x] 1.3.4.6 If `models[provider]` is empty/missing, fall back to provider's full model list
- [x] 1.3.4.7 Write tests verifying settings lists override dynamic discovery (success: custom lists used)
