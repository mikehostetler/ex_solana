# JidoHub Design System

## Design Vision

JidoHub's interface combines **Linear's sophisticated visual design** with **Slack's three-column workspace layout**, creating a focused, premium experience optimized for workflow automation and team collaboration.

### Core Aesthetic Principles

1. **Dark-first design** - Primary interface in sophisticated dark mode
2. **Generous whitespace** - Breathing room prevents visual clutter
3. **Subtle visual cues** - Refined borders, soft shadows, minimal decoration
4. **Modern typography** - Clean sans-serif with clear hierarchy
5. **Purposeful color** - Muted backgrounds with strategic accent use
6. **Micro-interactions** - Smooth transitions and polished details
7. **Keyboard-first interaction** - Command palette, hotkeys, and shortcuts as primary navigation

## Layout Architecture

### Three-Column Slack Pattern

```
┌─────────────────────────────────────────────────────────────────┐
│                         Navigation Header                        │
├──────┬────────────────┬──────────────────────┬──────────────────┤
│      │                │                      │                  │
│ Icon │    Channel     │    Main Content      │  Detail Sidebar  │
│ Menu │     List       │       Pane           │   (Collapsible)  │
│      │                │                      │                  │
│ 64px │     240px      │       flex-1         │      320px       │
│      │                │                      │                  │
└──────┴────────────────┴──────────────────────┴──────────────────┘
```

### Column Specifications

#### Column 1: Icon Menu (Left-most)
- **Width:** 64px fixed
- **Purpose:** Primary navigation icons
- **Content:** Logo, workspace switcher, main navigation icons
- **Behavior:** Always visible on desktop, hidden on mobile

#### Column 2: Channel/Context List
- **Width:** 240px fixed (desktop), collapsible
- **Purpose:** Contextual navigation (workflows, projects, teams)
- **Content:** Searchable list of channels/items with badges
- **Behavior:** Collapsible on tablet/mobile

#### Column 3: Main Working Pane
- **Width:** Flex-1 (grows to fill available space)
- **Purpose:** Primary content and interactions
- **Content:** Forms, tables, detail views, dashboards
- **Behavior:** Always visible, scrollable

#### Column 4: Detail Sidebar (Right-most)
- **Width:** 320px fixed
- **Purpose:** Contextual details, metadata, related actions
- **Content:** Properties, history, comments, related items
- **Behavior:** Collapsible, hidden by default on tablet/mobile

### Responsive Behavior

```
Desktop (≥1280px):  [Icon][List][Main][Sidebar]
Tablet (768-1279):  [Icon][List][Main] (sidebar collapsed)
Mobile (<768px):    [Main] (hamburger menu for icon+list)
```

## Theme & Color System

**See [THEME.md](docs/design/THEME.md) for complete theming implementation guide.**

### Quick Reference

**Themes:** `light`, `dark`, `cupcake`, `wireframe`, `business`, `nord`, `system`

**Switch theme:**
```heex
<button x-on:click="$store.theme.set('dark')">Dark</button>
```

**Required tokens:**
- Backgrounds: `bg-base-100`, `bg-base-200`, `bg-base-300`
- Text: `text-base-content` with `opacity-70` or `opacity-50`
- Borders: `border-base-300` (optionally `/40` for subtle)
- Buttons: `btn-primary`, `btn-secondary`, `btn-accent`, `btn-ghost`
- Status: `badge-success`, `badge-warning`, `badge-error`, `badge-info`

**Never hardcode colors.** Always use DaisyUI tokens.

## Typography

### Font Family

```css
font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", 
             Roboto, "Helvetica Neue", Arial, sans-serif;
```

### Type Scale

```css
/* Headings */
--text-6xl: 3.75rem;   /* 60px - Hero */
--text-5xl: 3rem;      /* 48px - Page title */
--text-4xl: 2.25rem;   /* 36px - Section */
--text-3xl: 1.875rem;  /* 30px - Subsection */
--text-2xl: 1.5rem;    /* 24px - Card title */
--text-xl: 1.25rem;    /* 20px - Small heading */
--text-lg: 1.125rem;   /* 18px - Large body */

/* Body */
--text-base: 1rem;     /* 16px - Default */
--text-sm: 0.875rem;   /* 14px - Small text */
--text-xs: 0.75rem;    /* 12px - Captions */
```

### Font Weights

```css
--font-normal: 400;    /* Body text */
--font-medium: 500;    /* Emphasis */
--font-semibold: 600;  /* Headings */
--font-bold: 700;      /* Strong emphasis */
```

### Line Heights

```css
--leading-tight: 1.25;    /* Headings */
--leading-snug: 1.375;    /* Dense text */
--leading-normal: 1.5;    /* Body text */
--leading-relaxed: 1.625; /* Comfortable reading */
--leading-loose: 2;       /* Spaced content */
```

## Spacing System

### Scale (Based on 4px grid)

```css
--space-0: 0;
--space-1: 0.25rem;  /* 4px */
--space-2: 0.5rem;   /* 8px */
--space-3: 0.75rem;  /* 12px */
--space-4: 1rem;     /* 16px */
--space-5: 1.25rem;  /* 20px */
--space-6: 1.5rem;   /* 24px */
--space-8: 2rem;     /* 32px */
--space-10: 2.5rem;  /* 40px */
--space-12: 3rem;    /* 48px */
--space-16: 4rem;    /* 64px */
--space-20: 5rem;    /* 80px */
--space-24: 6rem;    /* 96px */
```

### Usage Guidelines

- **Component padding:** 16px (space-4) to 24px (space-6)
- **Section spacing:** 32px (space-8) to 48px (space-12)
- **Page margins:** 48px (space-12) to 96px (space-24)
- **Element gaps:** 8px (space-2) to 16px (space-4)

### Generous Whitespace Philosophy

Following Linear's approach, use **2x more whitespace than feels necessary**:

```heex
<!-- Good: Generous breathing room -->
<div class="space-y-8 p-6">
  <h2 class="mb-4">Section Title</h2>
  <p class="mb-6">Content with space to breathe</p>
</div>

<!-- Avoid: Cramped spacing -->
<div class="space-y-2 p-2">
  <h2 class="mb-1">Section Title</h2>
  <p class="mb-2">Too tight</p>
</div>
```

## Borders & Dividers

### Border Styles

```css
/* Subtle borders - barely visible */
border: 1px solid rgba(255, 255, 255, 0.1);

/* Emphasized borders */
border: 1px solid rgba(255, 255, 255, 0.15);

/* Focus borders */
border: 1px solid var(--color-primary);
```

### Border Radius

```css
--radius-sm: 0.25rem;   /* 4px - Badges, tags */
--radius-md: 0.375rem;  /* 6px - Buttons, inputs */
--radius-lg: 0.5rem;    /* 8px - Cards, modals */
--radius-xl: 0.75rem;   /* 12px - Large containers */
--radius-full: 9999px;  /* Full round - avatars */
```

### Usage

- **Cards:** rounded-lg (8px)
- **Buttons:** rounded-md (6px)
- **Inputs:** rounded-md (6px)
- **Modals:** rounded-xl (12px)
- **Avatars:** rounded-full

## Shadows & Elevation

### Shadow Layers

```css
/* Subtle shadows - barely perceptible */
--shadow-xs: 0 1px 2px 0 rgba(0, 0, 0, 0.05);
--shadow-sm: 0 1px 3px 0 rgba(0, 0, 0, 0.1);
--shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
--shadow-lg: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
--shadow-xl: 0 20px 25px -5px rgba(0, 0, 0, 0.1);
```

### Usage Guidelines

1. **Cards at rest:** shadow-sm or none
2. **Cards on hover:** shadow-md
3. **Modals/Popovers:** shadow-lg
4. **Floating elements:** shadow-xl
5. **Active/Dragging:** shadow-xl with blur

### Elevation Principles

- Use shadows **sparingly** - only to indicate depth
- Keep shadows **soft and diffused** - never harsh
- Avoid "floating" everything - reserve for true elevation

## Keyboard-First Interaction

### Command Palette

The command palette is the primary navigation and action system, accessible via **Cmd+K** (Mac) or **Ctrl+K** (Windows/Linux).

#### Design Specifications

```heex
<!-- Command Palette Modal -->
<div class="fixed inset-0 z-50 flex items-start justify-center pt-[20vh] p-4 bg-black/50 backdrop-blur-sm">
  <div class="bg-base-200 rounded-xl shadow-xl max-w-2xl w-full overflow-hidden border border-base-300/40">
    <!-- Search Input -->
    <div class="flex items-center gap-3 px-4 py-3 border-b border-base-300/40">
      <.icon name="hero-magnifying-glass" class="w-5 h-5 text-base-content/50" />
      <input
        type="text"
        placeholder="Type a command or search..."
        class="flex-1 bg-transparent text-base-content placeholder:text-base-content/50 focus:outline-none"
        autofocus
      />
      <kbd class="px-2 py-1 text-xs rounded bg-base-300/40 text-base-content/70">ESC</kbd>
    </div>

    <!-- Results List -->
    <div class="max-h-96 overflow-y-auto p-2">
      <!-- Section: Quick Actions -->
      <div class="px-2 py-1 text-xs font-semibold text-base-content/50 uppercase tracking-wide">
        Quick Actions
      </div>
      <button class="w-full flex items-center gap-3 px-3 py-2 rounded-md hover:bg-base-300/40 text-left">
        <.icon name="hero-plus" class="w-5 h-5 text-base-content/70" />
        <span class="flex-1">Create Workflow</span>
        <kbd class="px-2 py-1 text-xs rounded bg-base-300/40 text-base-content/70">C</kbd>
      </button>

      <!-- Section: Navigation -->
      <div class="px-2 py-1 text-xs font-semibold text-base-content/50 uppercase tracking-wide mt-4">
        Navigation
      </div>
      <button class="w-full flex items-center gap-3 px-3 py-2 rounded-md hover:bg-base-300/40 text-left">
        <.icon name="hero-home" class="w-5 h-5 text-base-content/70" />
        <span class="flex-1">Dashboard</span>
        <kbd class="px-2 py-1 text-xs rounded bg-base-300/40 text-base-content/70">G D</kbd>
      </button>
    </div>

    <!-- Footer -->
    <div class="flex items-center justify-between px-4 py-2 border-t border-base-300/40 text-xs text-base-content/50">
      <span>Navigate with ↑↓</span>
      <span>Select with ⏎</span>
    </div>
  </div>
</div>
```

#### Command Categories

1. **Quick Actions**
   - Create new workflow (C)
   - Create new organization
   - Create new team
   - Import data

2. **Navigation**
   - Go to Dashboard (G D)
   - Go to Workflows (G W)
   - Go to Organizations (G O)
   - Go to Settings (G S)
   - Go to Notifications

3. **Search**
   - Search workflows
   - Search organizations
   - Search team members
   - Search documentation

4. **Recent**
   - Recently viewed workflows
   - Recently edited items
   - Recent activity

5. **Settings & Help**
   - Toggle theme
   - Keyboard shortcuts (?)
   - Documentation
   - Logout

#### Implementation Pattern

```javascript
// assets/js/command_palette.js
export const CommandPalette = {
  mounted() {
    this.handleKeyboard = (e) => {
      // Cmd+K or Ctrl+K
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        this.pushEvent("toggle-command-palette");
      }
    };
    
    window.addEventListener('keydown', this.handleKeyboard);
  },
  
  destroyed() {
    window.removeEventListener('keydown', this.handleKeyboard);
  }
};
```

### Global Keyboard Shortcuts

#### Two-Key Sequences (Gmail/GitHub Style)

Use **G** as the "Go to" prefix:

| Shortcut | Action | Context |
|----------|--------|---------|
| **G D** | Go to Dashboard | Global |
| **G W** | Go to Workflows | Global |
| **G O** | Go to Organizations | Global |
| **G S** | Go to Settings | Global |
| **G N** | Go to Notifications | Global |

#### Single-Key Actions

| Shortcut | Action | Context |
|----------|--------|---------|
| **C** | Create new (context-aware) | Global |
| **/** | Focus search | Global |
| **?** | Show keyboard shortcuts | Global |
| **Escape** | Close modal/palette | Global |
| **E** | Edit current item | Detail view |
| **D** | Delete current item | Detail view |
| **R** | Refresh/Reload | List view |

#### Modifier Combinations

| Shortcut | Action | Context |
|----------|--------|---------|
| **Cmd/Ctrl+K** | Open command palette | Global |
| **Cmd/Ctrl+S** | Save form | Forms |
| **Cmd/Ctrl+Enter** | Submit form | Forms |
| **Cmd/Ctrl+/** | Toggle sidebar | Dashboard |
| **Cmd/Ctrl+B** | Toggle channel list | Dashboard |

### Keyboard Shortcut Help Modal

Accessible via **?** key:

```heex
<div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
  <div class="bg-base-200 rounded-xl shadow-xl max-w-4xl w-full max-h-[80vh] overflow-hidden">
    <!-- Header -->
    <div class="px-6 py-4 border-b border-base-300/40 flex items-center justify-between">
      <h2 class="text-xl font-semibold">Keyboard Shortcuts</h2>
      <button class="text-base-content/70 hover:text-base-content">
        <.icon name="hero-x-mark" class="w-5 h-5" />
      </button>
    </div>

    <!-- Body - Two Column Grid -->
    <div class="p-6 overflow-y-auto grid md:grid-cols-2 gap-8">
      <!-- Column 1: Navigation -->
      <div>
        <h3 class="text-sm font-semibold text-base-content/70 uppercase tracking-wide mb-3">
          Navigation
        </h3>
        <div class="space-y-2">
          <div class="flex items-center justify-between py-2">
            <span class="text-sm">Open command palette</span>
            <kbd class="px-2 py-1 text-xs rounded bg-base-300/40">Cmd+K</kbd>
          </div>
          <div class="flex items-center justify-between py-2">
            <span class="text-sm">Go to Dashboard</span>
            <div class="flex gap-1">
              <kbd class="px-2 py-1 text-xs rounded bg-base-300/40">G</kbd>
              <kbd class="px-2 py-1 text-xs rounded bg-base-300/40">D</kbd>
            </div>
          </div>
        </div>
      </div>

      <!-- Column 2: Actions -->
      <div>
        <h3 class="text-sm font-semibold text-base-content/70 uppercase tracking-wide mb-3">
          Actions
        </h3>
        <div class="space-y-2">
          <div class="flex items-center justify-between py-2">
            <span class="text-sm">Create new</span>
            <kbd class="px-2 py-1 text-xs rounded bg-base-300/40">C</kbd>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
```

### Visual Keyboard Hints

#### Inline Hints in UI

Show keyboard shortcuts next to actions:

```heex
<button class="flex items-center justify-between w-full px-3 py-2 rounded-md hover:bg-base-200">
  <span class="flex items-center gap-2">
    <.icon name="hero-plus" class="w-4 h-4" />
    New Workflow
  </span>
  <kbd class="px-2 py-1 text-xs rounded bg-base-300/40 text-base-content/70">C</kbd>
</button>
```

#### KBD Component

```elixir
# CoreComponents
def kbd(assigns) do
  ~H"""
  <kbd class="inline-flex items-center gap-1 px-2 py-1 text-xs font-mono rounded bg-base-300/40 text-base-content/70 border border-base-300/60">
    {render_slot(@inner_block)}
  </kbd>
  """
end
```

Usage:
```heex
<.kbd>Cmd</.kbd> + <.kbd>K</.kbd>
```

### Implementation Requirements

1. **Global Keyboard Hook**
   - Mount on `window` via Phoenix Hook
   - Listen for all defined shortcuts
   - Prevent default browser behavior
   - Handle two-key sequences with timeout

2. **Command Palette LiveView**
   - Fuzzy search all commands
   - Recent commands memory
   - Context-aware command suggestions
   - Keyboard navigation (↑↓ arrows)

3. **Shortcut Registry**
   - Centralized definition of all shortcuts
   - Per-page/per-context shortcuts
   - Conflict detection
   - Dynamic help generation

4. **Visual Feedback**
   - Toast notifications for actions
   - Loading states for async commands
   - Error handling for failed commands

## Components

### Button Styles

#### Primary Action
```heex
<button class="
  px-4 py-2 rounded-md
  bg-primary text-white font-medium
  hover:bg-primary/90
  focus-visible:ring-2 focus-visible:ring-primary/40
  transition-all duration-200
  disabled:opacity-50 disabled:cursor-not-allowed
">
  Primary Action
</button>
```

#### Secondary Action
```heex
<button class="
  px-4 py-2 rounded-md
  bg-base-200 text-base-content font-medium
  hover:bg-base-300
  border border-base-300
  focus-visible:ring-2 focus-visible:ring-primary/40
  transition-all duration-200
">
  Secondary
</button>
```

#### Ghost/Minimal
```heex
<button class="
  px-4 py-2 rounded-md
  text-base-content/70 font-medium
  hover:bg-base-200 hover:text-base-content
  focus-visible:ring-2 focus-visible:ring-primary/40
  transition-all duration-200
">
  Ghost
</button>
```

### Card Styles

```heex
<div class="
  bg-base-200 rounded-lg
  border border-base-300/40
  p-6
  hover:shadow-md
  transition-shadow duration-200
">
  <h3 class="text-xl font-semibold mb-4">Card Title</h3>
  <p class="text-base-content/70">Card content with subtle styling</p>
</div>
```

### Input Styles

```heex
<input class="
  w-full px-3 py-2 rounded-md
  bg-base-100 text-base-content
  border border-base-300
  focus:border-primary focus:ring-2 focus:ring-primary/40
  placeholder:text-base-content/50
  transition-all duration-200
" />
```

### Navigation Elements

#### Icon Menu Item
```heex
<button class="
  w-12 h-12 flex items-center justify-center
  rounded-md
  text-base-content/70
  hover:bg-base-200 hover:text-base-content
  focus-visible:ring-2 focus-visible:ring-primary/40
  transition-all duration-200
">
  <.icon name="hero-home" class="w-6 h-6" />
</button>
```

#### Channel List Item
```heex
<button class="
  w-full px-3 py-2 rounded-md
  flex items-center gap-3
  text-left text-sm
  text-base-content/70
  hover:bg-base-200 hover:text-base-content
  aria-current:bg-primary/10 aria-current:text-primary
  transition-all duration-200
">
  <span class="flex-1 truncate">Channel Name</span>
  <span class="badge badge-sm">3</span>
</button>
```

## Micro-Interactions

### Transition Timing

```css
/* Fast interactions - hover, focus */
transition-duration: 150ms;
transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);

/* Medium interactions - expand/collapse */
transition-duration: 200ms;
transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);

/* Slow interactions - modals, page transitions */
transition-duration: 300ms;
transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
```

### Hover States

All interactive elements should have **subtle, fast** hover states:

```css
/* Opacity shift */
hover:opacity-90

/* Background change */
hover:bg-base-200

/* Border emphasis */
hover:border-primary/50

/* Shadow lift */
hover:shadow-md

/* Combined example */
hover:bg-base-200 hover:shadow-sm transition-all duration-150
```

### Focus States

Keyboard focus must be **highly visible**:

```css
focus-visible:outline-none
focus-visible:ring-2
focus-visible:ring-primary/40
focus-visible:ring-offset-2
focus-visible:ring-offset-base-100
```

### Loading States

```heex
<button
  class="px-4 py-2 rounded-md bg-primary text-white
         phx-submit-loading:opacity-60
         phx-submit-loading:cursor-wait"
  phx-disable-with="Saving..."
>
  Save Changes
</button>
```

## Iconography

### Icon Library

Use **Heroicons** (already integrated via `<.icon>` component):

```heex
<.icon name="hero-home" class="w-5 h-5" />
<.icon name="hero-cog-6-tooth" class="w-5 h-5" />
<.icon name="hero-user-circle" class="w-5 h-5" />
```

### Icon Sizes

```css
--icon-xs: 1rem;      /* 16px */
--icon-sm: 1.25rem;   /* 20px */
--icon-md: 1.5rem;    /* 24px */
--icon-lg: 2rem;      /* 32px */
--icon-xl: 3rem;      /* 48px */
```

### Icon Usage

- **Navigation:** 24px (w-6 h-6)
- **Buttons:** 20px (w-5 h-5)
- **Inline text:** 16px (w-4 h-4)
- **Headers:** 32px (w-8 h-8)
- **Empty states:** 48px (w-12 h-12)

## Layout Templates

### Dashboard Layout

```heex
<div class="flex h-screen bg-base-100">
  <!-- Icon Menu -->
  <aside class="w-16 bg-base-200 border-r border-base-300/40 flex flex-col items-center py-4 gap-2">
    <.icon name="hero-squares-2x2" class="w-6 h-6" />
    <.icon name="hero-rocket-launch" class="w-6 h-6" />
    <.icon name="hero-cog-6-tooth" class="w-6 h-6" />
  </aside>

  <!-- Channel/Context List -->
  <aside class="w-60 bg-base-200 border-r border-base-300/40 flex flex-col">
    <div class="p-4 border-b border-base-300/40">
      <input type="search" placeholder="Search..." class="input input-sm w-full" />
    </div>
    <nav class="flex-1 overflow-y-auto p-2">
      <!-- List items -->
    </nav>
  </aside>

  <!-- Main Content -->
  <main class="flex-1 flex flex-col overflow-hidden">
    <!-- Header -->
    <header class="h-16 border-b border-base-300/40 flex items-center px-6 gap-4">
      <h1 class="text-xl font-semibold">Page Title</h1>
    </header>

    <!-- Scrollable Content -->
    <div class="flex-1 overflow-y-auto p-6">
      <!-- Page content -->
    </div>
  </main>

  <!-- Detail Sidebar (Collapsible) -->
  <aside class="w-80 bg-base-200 border-l border-base-300/40 p-6 overflow-y-auto">
    <!-- Details panel -->
  </aside>
</div>
```

### Modal Layout

```heex
<div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
  <div class="bg-base-200 rounded-xl shadow-xl max-w-lg w-full max-h-[90vh] overflow-hidden">
    <!-- Header -->
    <div class="px-6 py-4 border-b border-base-300/40">
      <h2 class="text-xl font-semibold">Modal Title</h2>
    </div>

    <!-- Body -->
    <div class="px-6 py-4 overflow-y-auto">
      <!-- Modal content -->
    </div>

    <!-- Footer -->
    <div class="px-6 py-4 border-t border-base-300/40 flex justify-end gap-3">
      <.button variant="ghost">Cancel</.button>
      <.button variant="primary">Confirm</.button>
    </div>
  </div>
</div>
```

## Accessibility

### Focus Management

1. **Visible focus rings** on all interactive elements
2. **Skip navigation** links for screen readers
3. **Focus trap** in modals
4. **Focus restoration** after modal close

### ARIA Labels

```heex
<!-- Icon buttons need labels -->
<button aria-label="Close modal">
  <.icon name="hero-x-mark" />
</button>

<!-- Dynamic content needs live regions -->
<div role="status" aria-live="polite" aria-atomic="true">
  {@notification_message}
</div>

<!-- Modals need proper roles -->
<div role="dialog" aria-labelledby="modal-title" aria-describedby="modal-description">
  <h2 id="modal-title">Confirm Action</h2>
  <p id="modal-description">This action cannot be undone.</p>
</div>
```

### Keyboard Navigation

#### Standard Navigation
- **Tab:** Navigate forward through interactive elements
- **Shift+Tab:** Navigate backward
- **Enter:** Activate buttons/links
- **Escape:** Close modals/dropdowns/command palette
- **Arrow keys:** Navigate lists/menus

#### Command Palette
- **Cmd+K** (Mac) / **Ctrl+K** (Windows/Linux): Open command palette
- **Type to search:** Filter commands/pages/actions
- **Enter:** Execute selected command
- **Escape:** Close palette

#### Global Shortcuts
- **G then D:** Go to Dashboard
- **G then W:** Go to Workflows
- **G then O:** Go to Organizations
- **G then S:** Go to Settings
- **C:** Create new (context-aware)
- **/** Focus search
- **?:** Show keyboard shortcuts help

## DaisyUI Integration

### How We Use DaisyUI

1. **Theme tokens only** - Color/spacing variables from DaisyUI themes
2. **Wrapped primitives** - All DaisyUI classes wrapped in CoreComponents
3. **Never direct usage** - Never use DaisyUI classes in templates
4. **Custom theming** - Override DaisyUI theme in `app.css`

### Theme Configuration

Located in `assets/css/app.css`:

```css
@plugin "../vendor/daisyui" {
  themes: false;
}

@plugin "../vendor/daisyui-theme" {
  theme {
    dark {
      color-scheme: dark;
      primary: #8b5cf6;
      secondary: #6366f1;
      accent: #06b6d4;
      neutral: #18181b;
      base-100: #0d0d0e;
      base-200: #18181b;
      base-300: #27272a;
      base-content: #fafafa;
    }
  }
}
```

### CoreComponents Wrapping Pattern

```elixir
# lib/jido_hub_web/components/core_components.ex
def button(assigns) do
  assigns = assign_new(assigns, :variant, fn -> "primary" end)
  
  variant_classes = %{
    "primary" => "btn btn-primary",
    "secondary" => "btn btn-secondary",
    "ghost" => "btn btn-ghost"
  }
  
  ~H"""
  <button class={variant_classes[@variant]} {@rest}>
    {render_slot(@inner_block)}
  </button>
  """
end
```

## Implementation Checklist

### Essential Components
- [ ] Button (primary, secondary, ghost, danger)
- [ ] Input (text, email, password, textarea, select)
- [ ] Card (standard, bordered, hoverable)
- [ ] Modal (standard, confirm, form)
- [ ] Badge (status colors)
- [ ] Empty state
- [ ] Skeleton loader
- [ ] Navbar
- [ ] Sidebar navigation
- [ ] Table
- [ ] Form validation display
- [ ] KBD (keyboard shortcut display)
- [ ] Command Palette
- [ ] Keyboard Shortcuts Help Modal

### Layout Components
- [ ] Three-column dashboard shell
- [ ] Icon menu column
- [ ] Channel list column
- [ ] Main content area
- [ ] Collapsible detail sidebar
- [ ] Responsive mobile layout

### Interactions
- [ ] Hover states on all interactive elements
- [ ] Focus rings on all focusable elements
- [ ] Loading states on async actions
- [ ] Smooth transitions (150-300ms)
- [ ] Modal open/close animations
- [ ] Sidebar collapse/expand
- [ ] Command palette (Cmd+K / Ctrl+K)
- [ ] Global keyboard shortcuts (G D, G W, etc.)
- [ ] Keyboard shortcut help modal (?)
- [ ] Visual keyboard hints in UI

### Accessibility
- [ ] ARIA labels on icon buttons
- [ ] Focus management in modals
- [ ] Keyboard navigation working
- [ ] Skip navigation links
- [ ] Sufficient color contrast (WCAG AA)
- [ ] Screen reader testing

## Resources

- **Visual Inspiration:** [Linear](https://linear.app) - Dark mode sophistication
- **Layout Pattern:** Slack - Three-column workspace
- **Component Library:** DaisyUI wrapped in CoreComponents
- **Icons:** Heroicons via `<.icon>` component
- **Typography:** System font stack
- **Testing:** Phoenix.LiveViewTest + LazyHTML
