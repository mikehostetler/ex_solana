# Auto-Resume Session Feature

## Problem Statement

When starting JidoCode from a project directory, users must manually use `/resume` to restore their previous session for that project. This interrupts workflow and requires remembering that a saved session exists.

**Impact:**
- Extra steps to resume work on a project
- Users may forget they have a saved session and create duplicates
- Inconsistent experience compared to modern IDEs that restore state automatically

## Solution Overview

On startup, check if there's a persisted session matching the current working directory. If found, prompt the user with a confirmation dialog asking whether to resume the previous session or start fresh.

**Key Decisions:**
- Use confirmation dialog (not auto-resume silently) to give user control
- Reuse existing dialog widget patterns in the TUI
- Show relevant info in dialog: session name, when it was closed, message count

## Technical Details

### Files to Modify

- `lib/jido_code/tui.ex` - Add resume check in init, handle dialog state
- `lib/jido_code/session/persistence.ex` - Add `find_by_project_path/1` function

### Files to Create

- None (reuse existing dialog patterns)

### Existing Dialog Patterns

The TUI already has dialog support via:
- `shell_dialog` field in Model state
- `pick_list` field for selection dialogs
- Dialog rendering in view functions

### Implementation Approach

1. Add `find_by_project_path/1` to Persistence module
2. In TUI `init/1`, check for matching persisted session
3. If found, set a `resume_dialog` field with session info
4. Render dialog with "Resume" and "New Session" options
5. Handle dialog response to either resume or continue with new session

## Success Criteria

- [x] On startup, if persisted session exists for CWD, show confirmation dialog
- [x] Dialog shows session name, age, and message count
- [x] "Resume" option restores the previous session
- [x] "New Session" option creates fresh session (current behavior)
- [x] Tests cover the auto-resume flow
- [x] No regression in existing startup behavior

## Implementation Plan

### Step 1: Add Persistence lookup function
- [x] Add `find_by_project_path/1` to return persisted session for a path

### Step 2: Add dialog state to Model
- [x] Add `resume_dialog` field to Model struct
- [x] Add type for resume dialog state

### Step 3: Check for resumable session in init
- [x] In `init/1`, call `find_by_project_path(File.cwd!())`
- [x] If found, set `resume_dialog` with session metadata

### Step 4: Render resume confirmation dialog
- [x] Add `render_resume_dialog/1` function
- [x] Show session name, closed time, message count
- [x] Two buttons: "Resume (Enter)" and "New Session (Esc)"

### Step 5: Handle dialog input
- [x] Add event handlers for Enter (resume) and Esc (new session)
- [x] On resume: call Persistence.resume, add session to model
- [x] On new session: dismiss dialog, continue with fresh session

### Step 6: Add tests
- [x] Test `find_by_project_path/1`
- [x] Test dialog appears when persisted session exists
- [x] Test resume path works
- [x] Test new session path works

## Current Status

- **Phase**: Complete
- **What works**: Dialog appears on startup if resumable session exists, Enter resumes, Esc creates fresh
- **Tests**: 10 new tests added (4 in persistence_test.exs, 6 in tui_test.exs)

## Notes

- Dialog should be modal (block other input while shown)
- Consider edge case: what if resume fails? Show error and fall back to new session
- The dialog uses simple Enter/Esc keys rather than button widgets for simplicity
