# Phase 7: Theming and Styling

This phase adds theme support to provide consistent visual styling across the TUI with runtime theme switching capability using TermUI's built-in theme system.

## 7.1 Theme Infrastructure

### 7.1.1 Initialize Theme Server
- [x] **Task 7.1.1 Complete**

Add TermUI.Theme to the application supervision tree with dark as the default theme.

- [x] 7.1.1.1 Add TermUI.Theme to application.ex children list
- [x] 7.1.1.2 Configure theme: :dark as default option
- [x] 7.1.1.3 Load theme from settings if previously saved
- [x] 7.1.1.4 Ensure theme server starts before TUI components

## 7.2 Theme Command

### 7.2.1 Implement /theme Command
- [x] **Task 7.2.1 Complete**

Add /theme command for listing and switching themes at runtime.

- [x] 7.2.1.1 Add /theme parsing in Commands.parse_and_execute/2
- [x] 7.2.1.2 /theme without args lists available themes (dark, light, high_contrast)
- [x] 7.2.1.3 /theme <name> switches to the specified theme
- [x] 7.2.1.4 Validate theme name against TermUI.Theme.list_builtin/0
- [x] 7.2.1.5 Return appropriate success/error messages
- [x] 7.2.1.6 Write tests for /theme command (success: all tests pass)

### 7.2.2 Theme Persistence
- [x] **Task 7.2.2 Complete**

Persist theme selection across sessions via settings.

- [x] 7.2.2.1 Add "theme" field to settings schema
- [x] 7.2.2.2 Save selected theme to local settings on change
- [x] 7.2.2.3 Load and apply theme from settings on application startup

## 7.3 View Theme Integration

### 7.3.1 Update ViewHelpers to Use Theme
- [x] **Task 7.3.1 Complete**

Replace hardcoded Style.new() calls with theme-aware styles.

- [x] 7.3.1.1 Update border style to use Theme.get_component_style(:border, :focused)
- [x] 7.3.1.2 Update status bar to use theme colors
- [x] 7.3.1.3 Update message roles to use semantic colors (info for user, foreground for assistant, warning for system)
- [x] 7.3.1.4 Update tool call styles to use theme semantic colors
- [x] 7.3.1.5 Update reasoning panel styles to use theme
- [x] 7.3.1.6 Update input bar style to use theme

### 7.3.2 TUI Theme Subscription
- [x] **Task 7.3.2 Complete**

Subscribe TUI to theme changes for live updates.

- [x] 7.3.2.1 Subscribe to TermUI.Theme in TUI.init/1
- [x] 7.3.2.2 Handle {:theme_changed, theme} message in update/2
- [x] 7.3.2.3 Store current theme in TUI model for view access
- [x] 7.3.2.4 View automatically re-renders on theme change

## Success Criteria

- [x] All tests pass
- [x] Default theme is dark
- [x] /theme lists: dark, light, high_contrast
- [x] /theme <name> switches theme at runtime with immediate visual update
- [x] Theme selection persists across sessions
- [x] All UI components use theme colors consistently
