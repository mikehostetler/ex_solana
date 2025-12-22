# Work Sessions User Guide

JidoCode supports multiple concurrent work sessions, allowing you to work on different projects or contexts simultaneously without interference. This guide explains how to use the session system effectively.

## Table of Contents

- [What is a Session?](#what-is-a-session)
- [Creating Sessions](#creating-sessions)
- [Switching Between Sessions](#switching-between-sessions)
- [Managing Sessions](#managing-sessions)
- [Session Persistence](#session-persistence)
- [Session Limits](#session-limits)
- [Best Practices](#best-practices)

## What is a Session?

A **session** is an isolated workspace within JidoCode that includes:

- **Conversation history** - All messages between you and the AI agent
- **Project context** - The working directory for file operations
- **Session name** - A custom label for easy identification
- **Configuration** - LLM provider and model settings

Each session operates independently:
- Messages in one session don't affect others
- File operations are scoped to the session's project path
- Switching between sessions is instant

## Creating Sessions

### Create a Session for Current Directory

```
/session new
```

This creates a new session using your current working directory as the project path. The session name defaults to the directory name.

### Create a Session for a Specific Directory

```
/session new /path/to/project
```

Creates a session for the specified project directory.

### Create a Session with a Custom Name

```
/session new /path/to/project --name="My Project"
```

Use the `--name` flag to give your session a descriptive name. Session names:
- Can be up to 50 characters long
- Can include letters, numbers, spaces, hyphens, and underscores
- Help you quickly identify sessions when switching

### Examples

```
/session new ~/code/backend --name="Backend API"
/session new ~/code/frontend --name="React App"
/session new
```

## Switching Between Sessions

### Using Keyboard Shortcuts (Fastest)

- **Ctrl+1** through **Ctrl+9** - Switch to sessions 1-9
- **Ctrl+0** - Switch to session 10
- **Ctrl+Tab** - Switch to next session
- **Ctrl+Shift+Tab** - Switch to previous session

Keyboard shortcuts are the fastest way to navigate between sessions during active development.

### Using Session Commands

```
/session switch 2
```

Switch to session by index (shown in the tab bar).

```
/session switch my-project
```

Switch to session by name (case-insensitive partial match).

```
/session switch 019abc...
```

Switch to session by ID (full or partial match).

### Examples

```
/session switch backend
/session switch 3
/session switch 019a
```

## Managing Sessions

### List All Sessions

```
/session list
```

Shows all active sessions with:
- Index (for quick switching)
- Name
- Project path
- Message count

Example output:
```
Active Sessions:
  1. [Backend API] /home/user/code/backend (15 messages)
  2. [React App] /home/user/code/frontend (8 messages)
  3. [Database] /home/user/code/db (3 messages)
```

### Rename Current Session

```
/session rename "New Name"
```

Changes the name of the currently active session. Use quotes if the name contains spaces.

### Close Sessions

```
/session close
```

Closes the current session. The session is automatically saved before closing.

```
/session close 2
```

Closes session by index.

```
/session close backend
```

Closes session by name.

**Note**: Closing a session does NOT delete its data. You can resume closed sessions later.

### Close Session Keyboard Shortcut

- **Ctrl+W** - Close current session

### Creating New Sessions with Keyboard

- **Ctrl+N** - Opens new session dialog

## Session Persistence

Sessions are automatically saved when:
- You close a session with `/session close` or Ctrl+W
- You exit JidoCode normally

### Resuming Sessions

When you start JidoCode, you can resume your previous sessions:

```
/resume
```

Lists all saved sessions sorted by most recently closed.

```
/resume 1
```

Resume a session by index from the list.

```
/resume 019abc...
```

Resume a session by its ID.

### What Gets Saved?

Each saved session includes:
- **Conversation history** - All messages (up to 1000 messages)
- **Session metadata** - Name, project path, creation time
- **Configuration** - LLM provider and model settings

**What is NOT saved**:
- Streaming state (in-progress responses)
- Temporary UI state (scroll position, etc.)

### Storage Location

Sessions are saved in:
```
~/.jido_code/sessions/
```

Each session is stored in a separate JSON file with HMAC signature for integrity verification.

### Managing Saved Sessions

```
/resume delete 1
```

Delete a saved session by index.

```
/resume clear
```

Delete ALL saved sessions. **Use with caution** - this cannot be undone.

## Session Limits

JidoCode enforces some limits to ensure good performance:

### Maximum Active Sessions

**10 sessions** can be open simultaneously.

If you try to create an 11th session, you'll see:
```
Maximum sessions reached (10/10 sessions open). Close a session first.
```

**Solution**: Close an existing session with `/session close` or Ctrl+W.

### Maximum Messages Per Session

Each session can store up to **1000 messages**.

Older messages are automatically pruned when this limit is reached. This prevents memory issues and keeps performance fast.

### Session Name Length

Session names must be **50 characters or less**.

## Best Practices

### 1. Use Descriptive Session Names

Good names help you quickly identify sessions:

```
✅ Good: "Backend API", "React Frontend", "Database Schema"
❌ Poor: "Session 1", "Test", "Untitled"
```

### 2. Close Sessions When Done

Closing unused sessions:
- Frees up memory
- Makes room for new sessions
- Keeps your session list manageable

You can always resume them later with `/resume`.

### 3. One Session Per Project

Create separate sessions for different projects or major contexts:

```
/session new ~/work/project-a --name="Project A"
/session new ~/work/project-b --name="Project B"
```

This prevents file operations from mixing between projects.

### 4. Use Keyboard Shortcuts

Learn the keyboard shortcuts for maximum productivity:

- **Ctrl+N** - New session
- **Ctrl+1-0** - Switch to specific session
- **Ctrl+Tab** - Cycle through sessions
- **Ctrl+W** - Close current session

### 5. Resume Sessions for Context

When returning to a project after a break, resume the session to restore full conversation context:

```
/resume
> 1. [Backend API] /home/user/code/backend (closed 2 hours ago)
/resume 1
```

### 6. Keep Active Sessions Under 5

While you can have 10 active sessions, keeping 3-5 active sessions makes:
- Switching easier (keyboard shortcuts Ctrl+1-5)
- Session list more manageable
- Better memory usage

## Common Workflows

### Starting Your Day

```bash
# Resume your main projects
/resume
/resume 1  # Your main project
/resume 2  # Secondary project
```

### Working on Multiple Features

```bash
# Feature A
/session new ~/project --name="Feature A: Auth"
# ... work on auth feature ...

# Switch to Feature B
/session new ~/project --name="Feature B: UI"
# ... work on UI feature ...

# Quick switch back to Feature A
Ctrl+1
```

### Switching Between Projects

```bash
# Morning: Backend work
/session switch backend
# ... work on backend ...

# Afternoon: Frontend work
/session switch frontend
# ... work on frontend ...
```

### End of Day

```bash
# Close all sessions (auto-saves)
/session close backend
/session close frontend
/session close
```

## Troubleshooting

### "Session not found"

**Problem**: Tried to switch to a non-existent session.

**Solution**: Use `/session list` to see available sessions.

### "Maximum sessions reached"

**Problem**: Already have 10 sessions open.

**Solution**: Close a session with `/session close` or Ctrl+W.

### "Invalid session name"

**Problem**: Session name contains invalid characters or is too long.

**Solution**:
- Use only letters, numbers, spaces, hyphens, and underscores
- Keep names under 50 characters

### Lost Session After Crash

**Problem**: JidoCode crashed and session is gone.

**Solution**:
- Check `/resume` - sessions are auto-saved periodically
- If not listed, the session wasn't saved before the crash

## Next Steps

- See [Keyboard Shortcuts](keyboard-shortcuts.md) for a complete list of shortcuts
- See [Session FAQ](session-faq.md) for common questions and answers
- See `CLAUDE.md` for full command reference

## Getting Help

If you encounter issues with sessions:

1. Check this guide's [Troubleshooting](#troubleshooting) section
2. Check the [FAQ](session-faq.md)
3. Run `/help` in JidoCode for command reference
4. Report issues at https://github.com/jido/jido_code/issues
