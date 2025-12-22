# Keyboard Shortcuts Reference

This guide lists all keyboard shortcuts available in JidoCode, organized by category.

## Session Management

### Creating and Closing

| Shortcut | Action | Description |
|----------|--------|-------------|
| **Ctrl+N** | New Session | Opens new session dialog |
| **Ctrl+W** | Close Session | Closes current session (auto-saves) |

### Switching Sessions

| Shortcut | Action | Description |
|----------|--------|-------------|
| **Ctrl+1** | Switch to Session 1 | Jump to first session |
| **Ctrl+2** | Switch to Session 2 | Jump to second session |
| **Ctrl+3** | Switch to Session 3 | Jump to third session |
| **Ctrl+4** | Switch to Session 4 | Jump to fourth session |
| **Ctrl+5** | Switch to Session 5 | Jump to fifth session |
| **Ctrl+6** | Switch to Session 6 | Jump to sixth session |
| **Ctrl+7** | Switch to Session 7 | Jump to seventh session |
| **Ctrl+8** | Switch to Session 8 | Jump to eighth session |
| **Ctrl+9** | Switch to Session 9 | Jump to ninth session |
| **Ctrl+0** | Switch to Session 10 | Jump to tenth session |
| **Ctrl+Tab** | Next Session | Cycle to next session |
| **Ctrl+Shift+Tab** | Previous Session | Cycle to previous session |

**Note**: Session shortcuts only work when that many sessions are active. For example, Ctrl+5 only works if you have at least 5 sessions open.

## Configuration

| Shortcut | Action | Description |
|----------|--------|-------------|
| **Ctrl+M** | Model Selection | Opens model selection menu |
| **Ctrl+R** | Toggle Reasoning Panel | Show/hide chain-of-thought reasoning |

## Navigation Tips

### Quick Session Switching

For fastest navigation, use **Ctrl+1** through **Ctrl+9** when you have 3-5 active sessions:

```
Ctrl+1 → Main project
Ctrl+2 → Side project
Ctrl+3 → Experimental work
```

### Cycling Through Sessions

When you have many sessions and don't remember the index:

```
Ctrl+Tab, Ctrl+Tab, Ctrl+Tab → Cycle through until you find it
```

### Closing Workflow

Quick workflow to clean up sessions:

```
Ctrl+W → Close current
Ctrl+Tab → Move to next
Ctrl+W → Close that one
Ctrl+Tab → Move to next
```

## Platform-Specific Notes

### Linux/Windows

All shortcuts listed above work as-is.

### macOS

Replace **Ctrl** with **Cmd** (⌘):

- **Cmd+N** instead of Ctrl+N
- **Cmd+W** instead of Ctrl+W
- **Cmd+1-0** instead of Ctrl+1-0
- etc.

**Exception**: Ctrl+Tab and Ctrl+Shift+Tab remain the same on all platforms.

## Customization

Currently, keyboard shortcuts cannot be customized. This may change in future versions.

To request custom shortcuts support, please open an issue at:
https://github.com/jido/jido_code/issues

## Conflicts with Terminal Emulator

Some terminal emulators may intercept certain shortcuts before JidoCode receives them.

### Common Conflicts

| Shortcut | Typical Terminal Behavior | Solution |
|----------|---------------------------|----------|
| **Ctrl+W** | Delete word backward | Remap terminal shortcut or use `/session close` |
| **Ctrl+N** | New terminal window | Remap terminal shortcut or use `/session new` |
| **Ctrl+Tab** | Switch terminal tabs | Remap terminal shortcut |

### Recommended Solutions

1. **Disable conflicting shortcuts in your terminal**
   - Most terminals allow remapping or disabling shortcuts
   - Check your terminal's preferences/settings

2. **Use command alternatives**
   - Instead of Ctrl+W: `/session close`
   - Instead of Ctrl+N: `/session new`
   - Instead of Ctrl+1: `/session switch 1`

3. **Use a different terminal**
   - Some terminals have fewer default shortcuts
   - Examples: Alacritty, kitty, WezTerm

## Quick Reference Card

Print this for your desk:

```
╔═══════════════════════════════════════════╗
║     JidoCode Keyboard Shortcuts           ║
╠═══════════════════════════════════════════╣
║  Sessions:                                ║
║    Ctrl+N         New session             ║
║    Ctrl+W         Close session           ║
║    Ctrl+1 to 0    Switch to session 1-10  ║
║    Ctrl+Tab       Next session            ║
║    Ctrl+Shift+Tab Previous session        ║
║                                           ║
║  Configuration:                           ║
║    Ctrl+M         Model selection         ║
║    Ctrl+R         Toggle reasoning        ║
╚═══════════════════════════════════════════╝
```

## Learning the Shortcuts

### Start with These 3

Master these shortcuts first for 80% of the benefit:

1. **Ctrl+N** - Create new sessions quickly
2. **Ctrl+1, Ctrl+2, Ctrl+3** - Switch between your top 3 projects
3. **Ctrl+W** - Close sessions when done

### Add These Next

Once comfortable, add:

4. **Ctrl+Tab** - For quickly browsing through sessions
5. **Ctrl+M** - For changing models without typing commands

### Master Level

For maximum efficiency:

6. **Ctrl+4 through Ctrl+9** - Direct access to up to 9 sessions
7. **Ctrl+0** - Access to the 10th session
8. **Ctrl+Shift+Tab** - Reverse cycling through sessions

## See Also

- [Sessions User Guide](sessions.md) - Complete guide to using sessions
- [Session FAQ](session-faq.md) - Common questions and answers
- Main CLAUDE.md - Full command reference

## Getting Help

For issues with keyboard shortcuts:

1. Check this guide's [Conflicts](#conflicts-with-terminal-emulator) section
2. Check your terminal emulator's settings
3. Report bugs at https://github.com/jido/jido_code/issues
