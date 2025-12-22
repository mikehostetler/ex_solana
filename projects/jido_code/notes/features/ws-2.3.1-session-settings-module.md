# Feature: WS-2.3.1 Session Settings Module Structure

## Problem Statement

Task 2.3.1 requires creating the Session.Settings module for per-project settings. The existing `JidoCode.Settings` module uses `File.cwd!()` for the local path, which works for single-project scenarios. However, with per-session support, each session may have a different `project_path`, requiring a new module that accepts project path as a parameter.

## Solution Overview

Create `JidoCode.Session.Settings` module that:
- Provides path helpers accepting `project_path` parameter
- Documents the settings file path pattern: `{project_path}/.jido_code/settings.json`
- Documents merge priority: global < local (local overrides global)
- Follows patterns established by Session.Manager and Session.State

### Key Decisions

1. **Delegate to existing Settings module** - Reuse `JidoCode.Settings.read_file/1`, `validate/1`, and global path helpers
2. **Parameterized local paths** - All local path functions accept `project_path` argument
3. **Module structure only** - Task 2.3.1 is just structure; loading/saving is in 2.3.2-2.3.4

## Technical Details

### Files to Create

| File | Purpose |
|------|---------|
| `lib/jido_code/session/settings.ex` | Session.Settings module with path helpers |
| `test/jido_code/session/settings_test.exs` | Unit tests for path functions |

### Module Structure

```elixir
defmodule JidoCode.Session.Settings do
  @moduledoc """
  Per-session settings loader that respects project-local configuration.

  ## Settings Paths

  - Global: `~/.jido_code/settings.json` (managed by JidoCode.Settings)
  - Local: `{project_path}/.jido_code/settings.json`

  ## Merge Priority

  Local settings override global settings (global < local).
  """

  @local_dir_name ".jido_code"
  @settings_file "settings.json"

  @doc "Returns the local settings directory path for a project."
  @spec local_dir(String.t()) :: String.t()
  def local_dir(project_path)

  @doc "Returns the local settings file path for a project."
  @spec local_path(String.t()) :: String.t()
  def local_path(project_path)
end
```

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/jido_code/session/settings.ex`
- [x] Add @moduledoc with documentation
- [x] Define module attributes for directory and file names
- [x] Add `local_dir/1` function
- [x] Add `local_path/1` function

### Step 2: Write Unit Tests
- [x] Test `local_dir/1` returns correct path
- [x] Test `local_path/1` returns correct path
- [x] Test path functions handle various project paths

## Success Criteria

- [x] Module created with documentation
- [x] Path pattern documented: `{project_path}/.jido_code/settings.json`
- [x] Merge priority documented: global < local
- [x] Unit tests pass

## Current Status

**Status**: Complete

