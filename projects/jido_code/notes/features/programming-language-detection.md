# Feature Planning: Programming Language Detection

**Status**: Planning Complete - Ready for Implementation
**Created**: 2025-12-25
**Branch**: feature/programming-language-detection

---

## Problem Statement

JidoCode currently lacks awareness of the primary programming language used in a project. This information is valuable for:

1. **Providing language-specific assistance** - The LLM agent could tailor responses based on the project's primary language
2. **Status bar context** - Users can see at a glance what type of project they're working in
3. **Future enhancements** - Language-aware tool suggestions, syntax highlighting hints, context-aware completions

Currently:
- Sessions track project_path, name, and LLM config, but not the programming language
- No mechanism exists to detect language from project files
- No `/language` command for manual override
- Default behavior is undefined when language cannot be detected

---

## Solution Overview

Implement a language detection system that:
1. Automatically detects the primary language from project marker files
2. Provides a `/language` command for manual override
3. Stores the detected/set language in session state
4. Displays the current language in the TUI status bar
5. Falls back to `elixir` when no language can be detected

### Language Detection Rules

| File | Language |
|------|----------|
| `mix.exs` | elixir |
| `package.json` | javascript |
| `tsconfig.json` | typescript |
| `Cargo.toml` | rust |
| `pyproject.toml` | python |
| `requirements.txt` | python |
| `go.mod` | go |
| `Gemfile` | ruby |
| `pom.xml` | java |
| `build.gradle` / `build.gradle.kts` | java/kotlin |
| `*.csproj` | csharp |
| `composer.json` | php |
| `CMakeLists.txt` | cpp |
| `Makefile` + `.c` files | c |

Priority order: Check in the order listed above. First match wins.

---

## Technical Details

### Files to Create

1. **`lib/jido_code/language.ex`** - Language detection module
   - `detect/1` - Detect language from project path
   - `normalize/1` - Normalize language string to atom
   - `valid?/1` - Validate language value
   - `all_languages/0` - List all supported languages
   - `display_name/1` - Human-readable language name
   - `icon/1` - Icon for status bar display

### Files to Modify

1. **`lib/jido_code/session.ex`**
   - Add `:language` field to Session struct
   - Update `new/1` to call language detection
   - Add `set_language/2` function for manual override

2. **`lib/jido_code/session/state.ex`**
   - Add `update_language/2` function

3. **`lib/jido_code/session/persistence/serialization.ex`**
   - Add language to serialization/deserialization

4. **`lib/jido_code/session/persistence/schema.ex`**
   - Add language field to schema

5. **`lib/jido_code/commands.ex`**
   - Add `/language` command (show current)
   - Add `/language <lang>` (set language)

6. **`lib/jido_code/tui/view_helpers.ex`**
   - Update status bar to include language indicator

7. **`lib/jido_code/tui.ex`**
   - Add handler for language command results

---

## Implementation Plan

### Step 1: Create Language Detection Module ⬜

**File**: `lib/jido_code/language.ex`

**Tasks**:
- [ ] Create module with @detection_rules
- [ ] Implement `detect/1` function
- [ ] Implement `default/0` returning :elixir
- [ ] Implement `valid?/1` and `all_languages/0`
- [ ] Implement `normalize/1` for string/atom conversion
- [ ] Implement `display_name/1` for human-readable names
- [ ] Implement `icon/1` for status bar icons

### Step 2: Update Session Struct ⬜

**File**: `lib/jido_code/session.ex`

**Tasks**:
- [ ] Add `:language` to defstruct
- [ ] Add `language: language()` to type definition
- [ ] Update `new/1` to detect language from project_path
- [ ] Add `set_language/2` function

### Step 3: Update Session State ⬜

**File**: `lib/jido_code/session/state.ex`

**Tasks**:
- [ ] Add `update_language/2` client API
- [ ] Add `handle_call` for `{:update_language, language}`

### Step 4: Update Persistence ⬜

**Files**:
- `lib/jido_code/session/persistence/serialization.ex`
- `lib/jido_code/session/persistence/schema.ex`

**Tasks**:
- [ ] Add language to `build_persisted_session/1`
- [ ] Add language to `deserialize_session/1`
- [ ] Add `parse_language/1` helper
- [ ] Handle legacy sessions without language (default to elixir)

### Step 5: Add /language Command ⬜

**File**: `lib/jido_code/commands.ex`

**Tasks**:
- [ ] Add to @help_text
- [ ] Add `parse_and_execute` for "/language"
- [ ] Add `parse_and_execute` for "/language <lang>"

### Step 6: Update TUI Command Handling ⬜

**File**: `lib/jido_code/tui.ex`

**Tasks**:
- [ ] Add handler for `{:language, :show}`
- [ ] Add handler for `{:language, {:set, lang}}`
- [ ] Implement `handle_language_show/1`
- [ ] Implement `handle_language_set/2`

### Step 7: Update Status Bar ⬜

**File**: `lib/jido_code/tui/view_helpers.ex`

**Tasks**:
- [ ] Update `render_status_bar_with_session/3` to include language
- [ ] Add language icon to status bar display

### Step 8: Write Tests ⬜

**Files**:
- `test/jido_code/language_test.exs` (NEW)
- `test/jido_code/session_test.exs` (update)
- `test/jido_code/commands_test.exs` (update)

**Tests**:
- [ ] `detect/1` for each file type
- [ ] Default fallback to :elixir
- [ ] `valid?/1` for valid/invalid languages
- [ ] `normalize/1` for strings and atoms
- [ ] `display_name/1` for each language
- [ ] Session language auto-detection
- [ ] `/language` command parsing

---

## Success Criteria

- [ ] Creating session in Elixir project auto-detects `:elixir`
- [ ] Sessions in JS/Python/Rust projects detect correct language
- [ ] Projects without markers default to `:elixir`
- [ ] `/language` shows current language
- [ ] `/language python` changes session language
- [ ] Status bar displays language (e.g., "Elixir", "Python")
- [ ] Save/resume preserves language setting
- [ ] All existing tests pass

---

## Status Bar Format

Current format:
```
[1/3] project-name | ~/path | model | 🎟️ usage | status
```

New format:
```
[1/3] project-name | ~/path | Elixir | model | 🎟️ usage | status
```

---

## Notes

- Default language is `elixir` because JidoCode is an Elixir project
- Language detection happens once at session creation
- Manual override persists across session saves
- Future: Could add language-specific system prompts or tool suggestions

---

## Current Status

**What Works**: Planning complete
**What's Next**: Step 1 - Create Language detection module
**How to Run**: `mix jido_code`
