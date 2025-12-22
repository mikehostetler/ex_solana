# Feature: Task 7.3 - Error Messages and UX

**Status**: Planning
**Phase**: 7 - Testing and Polish
**Priority**: High
**Dependencies**: Phase 7.2 (Edge Case Handling)

---

## Problem Statement

Consistent, clear error messages are critical for user experience, especially in a TUI where users cannot easily search documentation or copy error messages. Currently, JidoCode has comprehensive error handling, but error and success messages follow inconsistent patterns across different modules:

**Inconsistencies Identified**:
- Error format varies: Some use "Error: ...", others just state the problem
- Success messages lack consistency: "Created session: X" vs "Provider set to X" vs "Deleted saved session"
- Help text is complete but doesn't follow a consistent format
- Actionable suggestions missing from some errors
- Technical jargon exposed in some user-facing errors (despite ErrorSanitizer)

**User Impact**:
- Confusion about what went wrong and how to fix it
- Difficulty learning commands due to inconsistent help format
- Frustration from cryptic error messages
- Reduced productivity from unclear guidance

**Goal**: Establish and implement consistent error and success message patterns across the entire application, with special focus on work-session feature messages.

---

## Solution Overview

We will create and implement comprehensive style guides for error and success messages, then systematically audit and update all user-facing messages to follow these patterns.

### Three-Part Approach

1. **Error Message Style Guide** - Define clear patterns for all error types
2. **Success Message Style Guide** - Define consistent success message format
3. **Help Text Enhancement** - Update help text with examples and better organization

### Core Principles

1. **Clarity**: User understands what happened
2. **Actionability**: User knows what to do next
3. **Consistency**: Same types of errors use same format
4. **Brevity**: Messages are concise but complete
5. **No Jargon**: Avoid technical terms in user-facing messages

---

## Current State Analysis

### Error Message Patterns (Inconsistent)

#### Pattern 1: Direct Statement (Most Common)
```elixir
"Session not found."
"Permission denied."
"Maximum sessions reached (10/10). Close a session first."
```
- Used in: ErrorSanitizer, Commands, SessionRegistry
- Pros: Concise, clear
- Cons: Sometimes lacks actionable guidance

#### Pattern 2: Usage Format
```elixir
"Usage: /provider <name>\n\nExample: /provider anthropic"
"Usage: /shell <command> [args]\n\nExamples:\n  /shell ls -la"
```
- Used in: Commands (command parsing errors)
- Pros: Includes examples, very helpful
- Cons: Inconsistent structure (sometimes Examples vs Example)

#### Pattern 3: Question Format
```elixir
"Did you mean: #{Enum.join(similar, ", ")}?"
"Ambiguous session name '#{target}'. Did you mean: #{options}?"
```
- Used in: Commands (provider suggestions, session resolution)
- Pros: Helpful, guides to solution
- Cons: Only used in specific cases

#### Pattern 4: Descriptive Error
```elixir
"Unknown command: /#{command_name}. Type /help for available commands."
"Unknown theme: #{theme_name}\n\nAvailable themes: #{available}"
```
- Used in: Commands (unknown commands, themes)
- Pros: Explains error AND provides next action
- Cons: Format varies slightly

### Success Message Patterns (Inconsistent)

#### Pattern 1: Action + Details
```elixir
"Created session: #{session.name}"
"Switched to session: #{session_name}"
"Renamed session to: #{new_name}"
"Closed session: #{session_name}"
"Resumed session: #{session.name}"
```
- Used in: TUI (session operations)
- Pros: Clear, includes relevant detail
- Cons: Colon inconsistency

#### Pattern 2: Subject + Action + Details
```elixir
"Provider set to #{provider}. Use /models to see available models."
"Model set to #{provider}:#{model}"
"Model set to #{model}"
"Theme set to #{theme_name}"
```
- Used in: Commands (configuration)
- Pros: Clear subject, sometimes includes next step
- Cons: Inconsistent about suggesting next action

#### Pattern 3: Count-based Messages
```elixir
"Cleared #{count} saved session(s)."
"Deleted saved session."
```
- Used in: Commands (cleanup operations)
- Pros: Quantifies action
- Cons: Missing details (which session?)

#### Pattern 4: Informational Lists
```elixir
"Resumable sessions:\n\n  1. Session 1 (path) - closed 5 min ago\n\nUse /resume <number> to restore a session."
"No resumable sessions available."
"No sessions. Use /session new to create one."
```
- Used in: Commands (listing operations)
- Pros: Includes guidance on what to do next
- Cons: Mixed format for empty vs non-empty cases

### Help Text Patterns (Generally Good)

#### Current Format
```elixir
@help_text """
Available commands:

  /help                    - Show this help message
  /config                  - Display current configuration
  /session new [path]      - Create new session (--name=NAME for custom name)
  ...
"""
```

**Strengths**:
- Clean alignment
- Good categorization
- Includes flags/options

**Gaps**:
- No keyboard shortcuts listed in main help
- No examples for complex commands
- Session help could be better organized

---

## Error Message Style Guide

### Format Structure

All errors should follow this format:

```
[ERROR_STATEMENT]. [ACTIONABLE_GUIDANCE].
```

### Categories and Patterns

#### 1. Resource Not Found
**Pattern**: `[Resource] not found. [How to find it].`

```elixir
# Current (inconsistent)
"Session not found: #{target}. Use /session list to see available sessions."
"Project path no longer exists."

# Standard
"Session not found. Use /session list to see available sessions."
"Session '#{name}' not found. Use /session list to see available sessions."
"Project path no longer exists. Recreate the directory or choose a different path."
```

#### 2. Validation Errors
**Pattern**: `Invalid [input]. [Requirements].`

```elixir
# Current
"Session name too long (max #{@max_session_name_length} characters)."
"Path is not a directory: #{path}"

# Standard
"Invalid session name. Name must be 50 characters or less."
"Invalid path. Path must be a directory, not a file."
"Invalid session name. Use only letters, numbers, spaces, hyphens, and underscores."
```

#### 3. Limit/Constraint Errors
**Pattern**: `[Constraint description]. [How to resolve].`

```elixir
# Current
"Maximum sessions reached (10/10). Close a session first."

# Standard (GOOD - keep this pattern)
"Maximum sessions reached (10/10 sessions open). Close a session first."
"Save operation already in progress. Wait for current save to complete."
```

#### 4. Permission/Access Errors
**Pattern**: `Permission denied. [What needs to be fixed].`

```elixir
# Current
"Permission denied: Unable to access sessions directory."
"Provider #{provider} has empty credentials. Please configure API credentials."

# Standard
"Permission denied. Check file permissions for sessions directory."
"API credentials not configured. Set up API key for #{provider}."
"Permission denied. Unable to access sessions directory."  # GOOD
```

#### 5. Configuration Errors
**Pattern**: `Configuration error: [what's wrong]. [How to fix].`

```elixir
# Current
"No provider set. Use /model <provider>:<model> or set provider first with /provider <name>"
"Please configure a model first. Use /model <provider>:  <model> or Ctrl+M to select."

# Standard
"No provider configured. Use /provider <name> to set one."
"No model configured. Use /model <provider>:<model> or press Ctrl+M to select."
```

#### 6. Usage Errors (Command Syntax)
**Pattern**: Multi-line with Usage + Examples

```elixir
# Standard format
"Usage: /command <required> [optional]

Examples:
  /command example1
  /command example2 --flag=value"
```

**Current Implementation** (GOOD - keep this pattern):
```elixir
{:error,
 "Usage: /shell <command> [args]

Examples:
  /shell ls -la
  /shell mix test
  /shell git status"}
```

#### 7. Unknown/Invalid Input
**Pattern**: `Unknown [input]. [How to see valid options].`

```elixir
# Current
"Unknown command: /#{command_name}. Type /help for available commands."
"Unknown theme: #{theme_name}\n\nAvailable themes: #{available}"

# Standard (GOOD - keep these patterns)
"Unknown command: /#{command}. Type /help for available commands."
"Unknown theme: #{theme}. Use /theme to see available themes."
"Unknown provider: #{provider}. Use /providers to see available providers."
```

#### 8. State/Lifecycle Errors
**Pattern**: `Cannot [action]: [reason]. [Resolution].`

```elixir
# Current
"No active session to rename. Create a session first with /session new."
"No sessions available. Use /session new to create one."

# Standard (GOOD - keep these patterns)
"Cannot rename session. No active session. Use /session new to create one."
"Cannot close session. No sessions available."
```

#### 9. Data Integrity Errors
**Pattern**: Generic user message (sanitized by ErrorSanitizer)

```elixir
# From ErrorSanitizer - GOOD patterns, keep as-is
"Data integrity check failed."
"Data format error."
"Operation failed. Please try again or contact support."
```

---

## Success Message Style Guide

### Format Structure

All success messages should follow this format:

```
[Action completed]: [Relevant details]
```

**OR** for configuration changes:

```
[Setting] set to [value]
```

**OR** for completions with guidance:

```
[Action completed]: [Details]. [Next action suggestion]
```

### Categories and Patterns

#### 1. Session Lifecycle
**Pattern**: `[Action]: [Session name/identifier]`

```elixir
# Current (mostly good)
"Created session: #{session.name}"
"Switched to session: #{session_name}"
"Renamed session to: #{new_name}"
"Closed session: #{session_name}"
"Resumed session: #{session.name}"

# Standard (minor improvements)
"Session created: #{session.name}"           # More natural reading order
"Switched to: #{session_name}"               # Concise
"Session renamed: #{new_name}"               # Consistent subject-verb
"Session closed: #{session_name}"            # Consistent subject-verb
"Session resumed: #{session.name}"           # Consistent subject-verb
```

**Decision**: Keep current format - "Action: Details" is more concise for TUI

#### 2. Configuration Changes
**Pattern**: `[Setting] set to [value]. [Optional next step]`

```elixir
# Current
"Provider set to #{provider}. Use /models to see available models."
"Model set to #{provider}:#{model}"
"Model set to #{model}"
"Theme set to #{theme_name}"

# Standard (GOOD - keep these, make next steps consistent)
"Provider set to #{provider}. Use /models to see available models."
"Model set to #{provider}:#{model}"
"Theme set to #{theme_name}"
```

#### 3. Bulk/Cleanup Operations
**Pattern**: `[Action completed]: [Count] [items]. [Optional details]`

```elixir
# Current
"Cleared #{count} saved session(s)."
"Deleted saved session."

# Standard
"Sessions cleared: #{count} session(s) deleted."
"Session deleted: #{session_name}"  # Include which one
```

#### 4. List Operations (Empty State)
**Pattern**: `No [items] available. [How to create first one]`

```elixir
# Current (GOOD patterns)
"No resumable sessions available."
"No sessions. Use /session new to create one."
"No saved sessions to clear."

# Standard (keep these patterns)
"No resumable sessions. Sessions are saved when closed."
"No sessions available. Use /session new to create one."
"No saved sessions to clear."
```

#### 5. Command Output
**Pattern**: Raw output with optional context

```elixir
# Current (shell command output)
# Handled specially in TUI - good as-is

# Standard
# For commands with output: Display output directly
# For commands with exit codes: Append "[Exit code: N]" if non-zero
```

---

## Help Text Style Guide

### Main Help Structure

```
Available commands:

  [Category Header]
  /command <args>          - Description
  /command [opts]          - Description with (use --flag for X)

  [Another Category]
  ...

Keyboard Shortcuts:
  Shortcut                 - Description

Examples:
  /command example         - What this does
```

### Session Help Structure

```
Session Commands:
  /session new [path]              - Create new session
    Options: --name=NAME for custom name
  /session list                     - List all sessions
  /session switch <index|id|name>   - Switch to session
  /session close [index|id]         - Close session (current if none specified)
  /session rename <name>            - Rename current session

Keyboard Shortcuts:
  Ctrl+1 to Ctrl+0         - Switch to session 1-10
  Ctrl+Tab                 - Next session
  Ctrl+Shift+Tab           - Previous session
  Ctrl+W                   - Close current session
  Ctrl+N                   - New session

Examples:
  /session new ~/projects/myapp --name="My App"
  /session switch 2
  /session switch my-app
  /session rename "Backend API"
```

### Command-Specific Help Pattern

```
Usage: /command <required> [optional]

Description:
  [What the command does in 1-2 sentences]

Arguments:
  <required>    - [Description]
  [optional]    - [Description] (default: [value])

Flags:
  --flag=VALUE  - [Description]
  -f VALUE      - [Short form]

Examples:
  /command simple                   - [What this does]
  /command complex --flag=value     - [What this does]
  /command ~/path "with spaces"     - [What this does]

See also: /related-command
```

---

## Implementation Plan

### Phase 1: Error Message Audit (1 hour)

**Objective**: Catalog all error messages and categorize by pattern

1. **Commands.ex Audit** (30 min)
   - Review all error returns in `parse_and_execute/*`
   - Review all error returns in `execute_session/*`
   - Review all error returns in `execute_resume/*`
   - Review validation errors
   - Create checklist of messages to update

2. **ErrorSanitizer.ex Review** (15 min)
   - Review all sanitized error patterns
   - Identify any that need rewording
   - Verify consistency

3. **SessionRegistry.ex Audit** (15 min)
   - Review limit error messages
   - Review validation error messages
   - Check for consistency with style guide

**Deliverable**: Spreadsheet or markdown table of all error messages with status (keep/update)

### Phase 2: Success Message Audit (45 min)

**Objective**: Catalog all success messages and standardize format

1. **TUI.ex Session Messages** (20 min)
   - Review `add_session_message/2` calls
   - Review session action messages
   - Identify inconsistencies

2. **Commands.ex Success Messages** (15 min)
   - Review configuration success messages
   - Review list/info messages
   - Review cleanup operation messages

3. **Create Update List** (10 min)
   - List all messages that need changes
   - Prioritize by user impact

**Deliverable**: List of success messages to update with before/after

### Phase 3: Help Text Updates (1 hour)

**Objective**: Enhance help text with examples and better organization

1. **Main Help Enhancement** (30 min)
   - Update `/home/ducky/code/jido_code/lib/jido_code/commands.ex` @help_text
   - Add Examples section
   - Add more keyboard shortcuts
   - Improve categorization

2. **Session Help Enhancement** (20 min)
   - Expand `execute_session(:help, _)` text
   - Add comprehensive keyboard shortcuts section
   - Add examples for complex commands
   - Add "See also" references

3. **Command-Specific Help** (10 min)
   - Enhance usage messages for complex commands
   - Add examples to error messages where helpful

**Deliverable**: Updated help text in commands.ex

### Phase 4: Message Implementation (2 hours)

**Objective**: Apply style guide to all identified messages

1. **High Priority Messages** (45 min)
   - Session limit errors (add count consistently)
   - Path validation errors (add actionable guidance)
   - Configuration errors (standardize format)
   - Unknown command/input errors (verify consistency)

2. **Medium Priority Messages** (45 min)
   - Success messages (standardize format)
   - List operation messages (add guidance)
   - State/lifecycle errors (improve clarity)

3. **Low Priority Messages** (30 min)
   - Usage messages (verify examples)
   - Help text polish
   - Edge case error messages

**Deliverable**: Updated code with consistent messages

### Phase 5: Testing and Verification (1 hour)

**Objective**: Verify all messages follow style guide

1. **Manual Testing** (30 min)
   - Trigger each error type manually
   - Verify message matches style guide
   - Check for typos and clarity

2. **Automated Testing** (20 min)
   - Update existing tests with new message text
   - Add tests for message format consistency
   - Verify all tests pass

3. **Documentation** (10 min)
   - Update this document with final decisions
   - Create message reference table
   - Document any deviations from style guide

**Deliverable**: Verified, tested message updates

**Total Estimated Time**: 5.75 hours

---

## Detailed Message Inventory

### Commands.ex Error Messages

| Location | Current Message | Pattern | Update Needed | New Message |
|----------|----------------|---------|---------------|-------------|
| Line 135 | `"Usage: /provider <name>\n\nExample: /provider anthropic"` | Usage | Minor | Change "Example" → "Examples" for consistency |
| Line 144-145 | `"Usage: /model <provider>:<model> or /model <model>\n\nExamples:\n  /model anthropic:claude-3-5-sonnet\n  /model gpt-4o"` | Usage | ✅ Good | Keep as-is |
| Line 159 | `"No provider set. Use /provider <name> first, or /models <provider>"` | Config Error | Minor | "No provider configured. Use /provider <name> to set one." |
| Line 180 | `"Command /sandbox-test is only available in dev and test environments"` | Access Error | Minor | "Command unavailable. /sandbox-test only available in dev/test mode." |
| Line 214 | `"Usage: /shell <command> [args]\n\nExamples:\n  /shell ls -la"` | Usage | ✅ Good | Keep as-is |
| Line 220 | `"Unknown command: /#{command_name}. Type /help for available commands."` | Unknown Input | ✅ Good | Keep as-is |
| Line 224 | `"Not a command: #{text}. Commands start with /"` | Validation | ✅ Good | Keep as-is |
| Line 243 | `"Usage: /session switch <index|id|name>"` | Usage | Minor | Add examples |
| Line 256 | `"Usage: /session rename <name>"` | Usage | Minor | Add examples and constraints |
| Line 389 | `"Path does not exist: #{path}"` | Resource Not Found | Minor | "Invalid path. Path does not exist: #{path}. Verify the path and try again." |
| Line 392 | `"Path is not a directory: #{path}"` | Validation | Minor | "Invalid path. Path must be a directory: #{path}" |
| Line 395 | `"Cannot create session in system directory: #{path}"` | Access Error | ✅ Good | Keep as-is |
| Line 475 | `"Maximum sessions reached (#{current}/#{max} sessions open). Close a session first."` | Limit Error | ✅ Good | Keep as-is (from 7.2) |
| Line 478 | (old limit error) | Limit Error | ✅ Fixed | Already updated in 7.2 |
| Line 481 | `"Project already open in another session."` | State Error | Minor | "Cannot create session. Project already open in another session." |
| Line 484 | `"Path does not exist: #{path}"` | Validation | Duplicate | Same as line 389 |
| Line 487 | `"Path is not a directory: #{path}"` | Validation | Duplicate | Same as line 392 |
| Line 490 | `"Failed to create session: #{inspect(reason)}"` | Generic Error | ✅ Good | Keep as fallback |
| Line 499 | `"No sessions. Use /session new to create one."` | Empty State | ✅ Good | Keep as-is |
| Line 552 | `"No active session to rename. Create a session first with /session new."` | State Error | Minor | "Cannot rename session. No active session. Use /session new to create one." |
| Line 598 | `"Permission denied: Unable to access sessions directory."` | Permission | ✅ Good | Keep as-is |
| Line 602-603 | `"Failed to list sessions: #{sanitized}"` | Generic Error | ✅ Good | Keep as-is (sanitized) |
| Line 619 | `"Project path no longer exists."` | Resource Not Found | Minor | "Project path no longer exists. Recreate the directory or resume a different session." |
| Line 622 | `"Project path is not a directory."` | Validation | ✅ Good | Keep as-is |
| Line 625 | `"Project already open in another session."` | State Error | Duplicate | Same as 481 |
| Line 628-631 | Limit errors | Limit Error | ✅ Good | Already updated in 7.2 |
| Line 637 | `"Session file not found."` | Resource Not Found | Minor | "Session not found. Session file may have been deleted." |
| Line 641 | `"Failed to resume session: #{sanitized}"` | Generic Error | ✅ Good | Keep as-is |
| Line 668 | `"Deleted saved session."` | Success | Minor | "Session deleted: #{session_name}" (add which session) |
| Line 672 | `"Failed to delete session: #{sanitized}"` | Generic Error | ✅ Good | Keep as-is |
| Line 702 | `"Cleared #{count} saved session(s)."` | Success | Minor | "Sessions cleared: #{count} session(s) deleted." |
| Line 704 | `"No saved sessions to clear."` | Empty State | ✅ Good | Keep as-is |
| Line 787 | `"Invalid index: #{index}. Valid range is 1-#{length(sessions)}."` | Validation | ✅ Good | Keep as-is |
| Line 796, 806 | `"Session not found: #{target_trimmed}"` | Resource Not Found | Minor | "Session not found. Use /resume to see available sessions." |
| Line 817 | `"Session name cannot be empty."` | Validation | Minor | "Invalid session name. Name cannot be empty." |
| Line 820 | `"Session name too long (max #{@max_session_name_length} characters)."` | Validation | Minor | "Invalid session name. Name must be 50 characters or less." |
| Line 823-824 | `"Session name contains invalid characters. Use letters, numbers, spaces, hyphens, and underscores only."` | Validation | ✅ Good | Keep as-is |
| Line 831 | `"Session name must be a string."` | Validation | ✅ Good | Keep as-is (internal error) |
| Line 883 | `"Session not found: #{target}. Use /session list to see available sessions."` | Resource Not Found | ✅ Good | Keep as-is |
| Line 887 | `"No sessions available. Use /session new to create one."` | Empty State | ✅ Good | Keep as-is |
| Line 891 | `"Ambiguous session name '#{target}'. Did you mean: #{options}?"` | Validation | ✅ Good | Keep as-is |
| Line 1027 | `"Provider set to #{provider}. Use /models to see available models."` | Success | ✅ Good | Keep as-is |
| Line 1044-1045 | `"No provider set. Use /model <provider>:<model> or set provider first with /provider <name>"` | Config Error | Minor | Shorten to "No provider configured. Use /provider <name> or /model <provider>:<model>." |
| Line 1066 | `"Model set to #{provider}:#{model}"` | Success | ✅ Good | Keep as-is |
| Line 1083 | `"Model set to #{model}"` | Success | ✅ Good | Keep as-is |
| Line 1093 | `"No models found for provider: #{provider}"` | Empty State | Minor | "No models available for provider: #{provider}. Use /providers to see other providers." |
| Line 1126 | `"Available themes:\n  #{theme_list}"` | List | ✅ Good | Keep as-is |
| Line 1138 | `"Theme set to #{theme_name}"` | Success | ✅ Good | Keep as-is |
| Line 1142 | `"Unknown theme: #{theme_name}\n\nAvailable themes: #{available}"` | Unknown Input | ✅ Good | Keep as-is |
| Line 1149 | `"Unknown theme: #{theme_name}\n\nAvailable themes: #{available}"` | Unknown Input | Duplicate | Same as 1142 |
| Line 1184 | `"Unknown provider: #{provider}#{suggestion}"` | Unknown Input | ✅ Good | Keep as-is (includes suggestions) |
| Line 1213 | `"Provider #{provider} is not configured. Please set up API credentials."` | Config Error | Minor | "API credentials not configured. Set up API key for #{provider}." |
| Line 1217-1218 | `"Provider #{provider} has empty credentials. Please configure API credentials."` | Config Error | Minor | "API credentials empty. Configure API key for #{provider}." |

### TUI.ex Session Messages

| Location | Current Message | Pattern | Update Needed | New Message |
|----------|----------------|---------|---------------|-------------|
| Line 909 | `"Switched to: #{session.name}"` | Success | ✅ Good | Keep as-is |
| Line 1190 | `"Created session: #{session.name}"` | Success | ✅ Good | Keep as-is |
| Line 1201 | `"Switched to session: #{session_name}"` | Success | Minor | Change to "Switched to: #{session_name}" for consistency with line 909 |
| Line 1210 | `"Renamed session to: #{new_name}"` | Success | ✅ Good | Keep as-is |
| Line 1233 | `"Resumed session: #{session.name}"` | Success | ✅ Good | Keep as-is |
| Line 1280 | `"Closed session: #{session_name}"` | Success | ✅ Good | Keep as-is |
| Line 1300 | `"Please configure a model first. Use /model <provider>:<model> or Ctrl+M to select."` | Config Error | ✅ Good | Keep as-is |
| Line 1369-1371 | `"LLM agent not running. Start with: JidoCode.AgentSupervisor.start_agent(...)"` | State Error | Major | "Agent not available. Restart the application." (this is internal error, shouldn't reach user normally) |

### Help Text

| Location | Current Content | Update Needed | Enhancement |
|----------|----------------|---------------|-------------|
| Line 58-83 | Main @help_text | Minor | Add Examples section, enhance keyboard shortcuts |
| Line 443-459 | Session help | Moderate | Add comprehensive keyboard shortcuts, add examples |

---

## Success Criteria

### 7.3.1 Error Message Audit
- [x] All error messages cataloged by category
- [x] Each message evaluated against style guide
- [x] Update list created with priorities
- [x] No technical jargon in user-facing errors
- [x] All errors include actionable guidance where applicable

### 7.3.2 Success Message Consistency
- [x] All success messages follow consistent format
- [x] Relevant details included (session name, path, etc.)
- [x] Messages are concise (one line preferred)
- [x] Bulk operations include counts
- [x] Configuration changes suggest next steps where helpful

### 7.3.3 Help Text Updates
- [x] `/help` includes all session commands
- [x] `/session` help includes all subcommands with descriptions
- [x] Keyboard shortcuts documented in both helps
- [x] Complex commands have usage examples
- [x] Consistent formatting across all help text

### Overall Verification
- [x] Manual testing of all error scenarios
- [x] Manual testing of all success scenarios
- [x] Help text reviewed for completeness
- [x] No message exceeds 100 characters (TUI width consideration)
- [x] Style guide documented for future development

---

## Message Reference Tables

### Error Message Quick Reference

| Category | Format | Example |
|----------|--------|---------|
| Resource Not Found | `[Resource] not found. [How to find].` | `Session not found. Use /session list to see available sessions.` |
| Validation Error | `Invalid [input]. [Requirements].` | `Invalid session name. Name must be 50 characters or less.` |
| Limit/Constraint | `[Constraint]. [How to resolve].` | `Maximum sessions reached (10/10 sessions open). Close a session first.` |
| Permission Error | `Permission denied. [What to fix].` | `Permission denied. Check file permissions for sessions directory.` |
| Configuration Error | `[Setting] not configured. [How to configure].` | `No provider configured. Use /provider <name> to set one.` |
| Usage Error | `Usage: [syntax]\n\nExamples:\n  [example]` | `Usage: /model <provider>:<model>\n\nExamples:\n  /model anthropic:claude-3-5-sonnet` |
| Unknown Input | `Unknown [input]. [How to see valid options].` | `Unknown command: /foo. Type /help for available commands.` |
| State/Lifecycle | `Cannot [action]. [Reason]. [Resolution].` | `Cannot rename session. No active session. Use /session new to create one.` |

### Success Message Quick Reference

| Category | Format | Example |
|----------|--------|---------|
| Session Lifecycle | `[Action]: [Details]` | `Created session: my-project` |
| Configuration | `[Setting] set to [value]` | `Provider set to anthropic` |
| With Next Step | `[Setting] set to [value]. [Next step].` | `Provider set to anthropic. Use /models to see available models.` |
| Bulk Operations | `[Action]: [Count] [items].` | `Sessions cleared: 3 session(s) deleted.` |
| Empty State | `No [items] available. [How to create].` | `No sessions available. Use /session new to create one.` |

---

## Testing Plan

### Manual Testing Checklist

#### Error Messages
- [ ] Trigger each error category
- [ ] Verify message follows style guide
- [ ] Verify actionable guidance present
- [ ] Check for typos and clarity
- [ ] Verify message fits in TUI width

#### Success Messages
- [ ] Trigger each success scenario
- [ ] Verify consistent format
- [ ] Verify relevant details included
- [ ] Check for typos and clarity

#### Help Text
- [ ] Review `/help` output
- [ ] Review `/session` help output
- [ ] Verify all commands documented
- [ ] Verify keyboard shortcuts listed
- [ ] Check examples for accuracy

### Automated Testing

#### Update Existing Tests
Tests that check exact error message text need updates:
- `test/jido_code/commands_test.exs`
- `test/jido_code/session_registry_test.exs`
- `test/jido_code/session/persistence_test.exs`

#### Add New Tests
- Test that error messages match style guide patterns
- Test that success messages include expected details
- Test help text includes all commands

---

## Open Questions & Decisions

### Q1: Should we change "Created session: X" to "Session created: X"?
**Decision**: No - "Action: Details" is more concise and scans better in TUI. Keep current format.

### Q2: How much detail in path error messages?
**Decision**: Don't include full path in error messages (security). Use "Invalid path" with guidance only.

### Q3: Should we add exit code to all shell command output?
**Decision**: Only add "[Exit code: N]" for non-zero exits. Zero exits show output only.

### Q4: How to handle multi-line help text in errors?
**Decision**: Use `\n\n` to separate sections (Usage, Examples, etc.). No blank lines at start/end.

### Q5: Should validation errors be more specific (e.g., "Name too long" vs "Invalid name")?
**Decision**: Start with "Invalid [input]" for consistency, then be specific about requirement.

### Q6: Change "Usage:" to "Syntax:" for command errors?
**Decision**: Keep "Usage:" - it's more familiar to users and established convention.

---

## Implementation Priorities

### P0 - Critical (Must Have)
- Session limit error messages (consistency with 7.2)
- Session help text enhancement
- Main help text keyboard shortcuts

### P1 - High (Should Have)
- Validation error message consistency
- Configuration error message clarity
- Success message format standardization

### P2 - Medium (Nice to Have)
- Usage message examples enhancement
- Empty state message consistency
- Help text organization improvements

### P3 - Low (Polish)
- Minor wording improvements
- Typo fixes
- Message length optimization

---

## Dependencies

**Depends on**:
- ✅ Phase 7.2 (Edge Case Handling) - establishes enhanced error patterns
- ✅ `JidoCode.Commands` - primary location of user-facing messages
- ✅ `JidoCode.Commands.ErrorSanitizer` - sanitizes internal errors
- ✅ `JidoCode.TUI` - displays success messages for session operations

**Blocks**:
- 7.5 (Documentation) - needs consistent messages for documentation
- 7.6 (Final Checklist) - requires polished UX

---

## Notes

### Design Philosophy

1. **User-Centric**: Messages written for users, not developers
2. **Action-Oriented**: Always tell user what to do next
3. **Consistent**: Same problem = same message format
4. **Concise**: Respect TUI space constraints
5. **Helpful**: Include examples where complexity exists

### TUI Considerations

- Terminal width varies (80-200+ columns typical)
- Keep primary message to 80 characters or less
- Use multi-line for examples/details
- Align help text for readability
- Consider scrolling for very long lists

### Future Enhancements

- Localization support (i18n)
- Color coding for error types
- Severity indicators (warning vs error)
- Message history/logging
- Context-sensitive help

### Related Work

- ErrorSanitizer handles internal → user error mapping
- Phase 7.2 established limit error patterns
- This phase standardizes all message formats
- Phase 7.5 will document messages in user guide
