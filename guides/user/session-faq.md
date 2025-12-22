# Session FAQ

Common questions and answers about JidoCode's work-session feature.

## General Questions

### What is a work session?

A work session is an isolated workspace in JidoCode that includes your conversation history, project context, and configuration. Each session operates independently, allowing you to work on multiple projects or contexts without interference.

### How many sessions can I have?

You can have up to **10 sessions open simultaneously**. There's no limit on how many sessions you can save and resume later.

### Are sessions saved automatically?

Yes! Sessions are automatically saved when you:
- Close a session with `/session close` or Ctrl+W
- Exit JidoCode normally

Sessions are NOT saved if JidoCode crashes unexpectedly.

### Where are my sessions stored?

Sessions are saved in `~/.jido_code/sessions/` as JSON files with HMAC signatures for integrity verification.

## Creating and Managing Sessions

### Can I create a session without a project path?

No, every session must have a project path. If you don't specify one, the current working directory is used automatically.

### Can two sessions use the same project path?

Yes! You can have multiple sessions for the same project. This is useful for:
- Working on different features in parallel
- Comparing different approaches
- Testing vs. development conversations

However, each session must have a unique name to distinguish them.

### Can I change a session's project path after creation?

No, the project path is set when the session is created and cannot be changed. If you need a different path, create a new session with the correct path.

### How do I rename a session?

Use the `/session rename` command:

```
/session rename "New Name"
```

This only works for the currently active session.

### Can I duplicate a session?

Not directly. To get similar functionality:
1. Close the session you want to duplicate (saves it)
2. Resume it twice:
   ```
   /resume 1
   /resume 1
   ```
3. Rename one of them:
   ```
   /session rename "Copy of Original"
   ```

This creates two independent sessions with the same starting conversation.

## Session Persistence

### What happens to my conversation history?

Your conversation history (up to 1000 messages) is saved with the session. When you resume a session, all messages are restored.

### Are reasoning steps saved?

Yes, reasoning steps are saved as part of the conversation history (up to 100 reasoning steps per session).

### Are tool calls saved?

Yes, tool call history is saved (up to 500 tool calls per session).

### Is streaming state saved?

No, if you close a session while the AI is streaming a response, that partial response is lost. Wait for responses to complete before closing sessions.

### Can I export a session?

Not currently. Session files are in `~/.jido_code/sessions/` but are internal format. Export functionality may be added in the future.

### Can I import sessions from another machine?

Yes! Copy the session JSON files from `~/.jido_code/sessions/` on one machine to the same location on another. The HMAC signatures will still be valid.

## Session Limits and Performance

### Why is there a 10 session limit?

The limit ensures good performance and prevents excessive memory usage. With 10 sessions, JidoCode uses approximately 50-100MB of memory.

### Why is there a 1000 message limit per session?

The limit prevents memory issues and keeps performance fast. When you reach 1000 messages, older messages are automatically pruned.

**Tip**: If you need a fresh start, create a new session for the same project.

### What happens when I reach 1000 messages?

Older messages are automatically removed, keeping the most recent 1000. This happens transparently - you won't see any warning.

### How much disk space do sessions use?

Typical session sizes:
- Empty session: ~1 KB
- 100 messages: ~50 KB
- 500 messages: ~250 KB
- 1000 messages: ~500 KB

With 10 saved sessions at maximum size: ~5 MB total.

### Does switching sessions slow down JidoCode?

No! Session switching is extremely fast (< 5ms typically). The switch only updates which session is active - no data loading required.

## Keyboard Shortcuts

### Why isn't Ctrl+W working?

Your terminal emulator may be intercepting the shortcut. Solutions:
1. Remap or disable Ctrl+W in your terminal settings
2. Use the command instead: `/session close`

See the [Keyboard Shortcuts Guide](keyboard-shortcuts.md) for more details.

### Can I customize keyboard shortcuts?

Not currently. Shortcut customization may be added in a future version.

### Do shortcuts work on macOS?

Yes, but use **Cmd** instead of **Ctrl**:
- Cmd+N instead of Ctrl+N
- Cmd+W instead of Ctrl+W
- Cmd+1-0 instead of Ctrl+1-0

Exception: Ctrl+Tab and Ctrl+Shift+Tab remain the same on all platforms.

## Troubleshooting

### I closed a session by accident. Can I get it back?

Yes! Use `/resume` to see all closed sessions and resume it:

```
/resume
> 1. [My Project] /home/user/project (closed 5 minutes ago)
/resume 1
```

### My session isn't in the `/resume` list

Possible reasons:
1. **Session was deleted**: Check if you ran `/resume delete` or `/resume clear`
2. **Session file corrupted**: Check `~/.jido_code/sessions/` for the file
3. **JidoCode crashed before save**: Sessions are only saved on normal close/exit

### I get "Session not found" when trying to switch

Use `/session list` to see available sessions. The session you're trying to switch to may have been closed or doesn't exist.

### I can't create a new session ("Maximum sessions reached")

You already have 10 sessions open. Close one first:

```
/session list         # See all sessions
/session close 3      # Close one by index
/session new /path    # Now create new one
```

### Session switching seems broken

Check:
1. **Do you have multiple sessions?** Run `/session list` to verify
2. **Is the index correct?** Ctrl+5 only works if you have at least 5 sessions
3. **Terminal intercepts?** Try the command instead: `/session switch 2`

### Messages from different sessions are mixed up

This shouldn't happen - sessions are isolated. If you're seeing this:
1. Verify which session is active: Look at the tab bar or run `/session list`
2. Restart JidoCode
3. Report the bug: https://github.com/jido/jido_code/issues

## Advanced Usage

### Can I have different LLM models per session?

Yes! Each session has its own configuration. Change models in one session without affecting others:

```
/session switch backend
/model anthropic:claude-3-5-sonnet

/session switch frontend
/model openai:gpt-4
```

### Can I run commands across all sessions?

No, commands only affect the active session. To run commands in multiple sessions:
1. Switch to each session
2. Run the command
3. Switch to next session

### Can sessions communicate with each other?

No, sessions are completely isolated. Each session has:
- Independent conversation history
- Separate project context
- Isolated file operations
- Independent tool execution

### How do I organize many saved sessions?

Best practices:
1. **Use descriptive names**: "Project A - Feature X" instead of "Session 1"
2. **Clean up regularly**: Delete old sessions with `/resume delete <index>`
3. **Group by project**: Use naming conventions like "ProjectA-Feature1", "ProjectA-Feature2"
4. **Keep only active work**: Delete completed project sessions

### Can I share sessions with teammates?

Yes, by copying session files:
1. Find session file in `~/.jido_code/sessions/`
2. Share the JSON file with teammates
3. They copy it to their `~/.jido_code/sessions/` directory
4. They resume it with `/resume`

**Note**: Sessions include full conversation history, so only share with trusted teammates.

## Best Practices

### When should I create a new session vs. continue existing?

**Create new session when**:
- Starting work on a different project
- Switching between major features
- Need fresh context (> 1000 messages in current)
- Want to try different approaches in parallel

**Continue existing session when**:
- Building on previous conversation
- Iterating on current feature
- Context is still relevant
- Session has < 500 messages

### How many sessions should I keep active?

**Recommended**: 3-5 active sessions

**Reasoning**:
- Easy to switch with Ctrl+1-5
- Manageable session list
- Good memory usage
- Enough for most workflows

### Should I close sessions every day?

**Recommended**: Yes, at end of work session

**Benefits**:
- Frees memory
- Auto-saves conversations
- Clean start next day
- Easy to resume what matters

Use `/resume` the next day to continue where you left off.

## Getting More Help

- [Sessions User Guide](sessions.md) - Complete session documentation
- [Keyboard Shortcuts](keyboard-shortcuts.md) - All keyboard shortcuts
- Main CLAUDE.md - Full command reference
- Report bugs: https://github.com/jido/jido_code/issues
