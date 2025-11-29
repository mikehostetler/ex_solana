# Theme System

## Overview

JidoHub uses DaisyUI themes with Alpine.js store for dynamic switching and localStorage persistence.

**Available themes:** `light` (default), `dark` (prefersdark), `cupcake`, `wireframe`, `business`, `nord`, `system` (auto-detects OS)

## Implementation

### Alpine.js Store (`assets/js/alpine/theme_store.js`)

```javascript
Alpine.store('theme', {
  value: 'system',
  init() {
    const stored = localStorage.getItem('jido_hub:theme') || 'system';
    this.set(stored);
  },
  set(theme) {
    this.value = theme;
    localStorage.setItem('jido_hub:theme', theme);
    if (theme === 'system') {
      theme = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    }
    document.documentElement.setAttribute('data-theme', theme);
  },
  is(theme) { return this.value === theme; }
});
```

### Template Usage

**Switch theme:**
```heex
<button x-on:click="$store.theme.set('dark')">Dark</button>
```

**Show active state:**
```heex
<button x-bind:class="{ 'btn-active': $store.theme.is('dark') }">Dark</button>
```

**Display current:**
```heex
<span x-text="$store.theme.value"></span>
```

### FOUC Prevention (`root.html.heex`)

```heex
<script>
  (function() {
    const theme = localStorage.getItem('jido_hub:theme') || 'system';
    let applied = theme === 'system' 
      ? (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')
      : theme;
    document.documentElement.setAttribute('data-theme', applied);
  })();
</script>
```

## Color Token Rules

**ALWAYS use DaisyUI tokens. NEVER hardcode colors.**

### Token Reference

| Token | Usage |
|-------|-------|
| `bg-base-100` | Page background |
| `bg-base-200` | Cards, sidebars, elevated surfaces |
| `bg-base-300` | Borders, dividers |
| `text-base-content` | All text (use `opacity-*` for hierarchy) |
| `btn-primary` | Primary actions |
| `btn-secondary` | Secondary actions |
| `btn-accent` | Accent actions |
| `btn-ghost` | Minimal buttons |
| `badge-success` | Success states |
| `badge-warning` | Warning states |
| `badge-error` | Error states |
| `badge-info` | Info states |

### Text Hierarchy

```heex
<h1 class="text-base-content">Primary</h1>
<p class="text-base-content opacity-70">Secondary</p>
<span class="text-base-content opacity-50">Tertiary</span>
```

### Background Levels

```heex
<body class="bg-base-100">
  <div class="bg-base-200 border border-base-300">
    <div class="bg-base-300">Nested</div>
  </div>
</body>
```

### Borders

```heex
<div class="border border-base-300">Standard</div>
<div class="border border-base-300/40">Subtle</div>
```

## Examples

**Card:**
```heex
<div class="bg-base-200 border border-base-300 rounded-lg p-6">
  <h3 class="text-base-content font-semibold mb-2">Title</h3>
  <p class="text-base-content opacity-70">Description</p>
  <button class="btn btn-primary">Action</button>
</div>
```

**Form input:**
```heex
<input class="input input-bordered bg-base-100 border-base-300 text-base-content" />
```

**List item:**
```heex
<button class="w-full px-4 py-2 rounded-lg hover:bg-base-300/40">
  <span class="text-base-content">Item</span>
</button>
```

## Common Mistakes

| ❌ Wrong | ✅ Correct |
|---------|-----------|
| `bg-white` `dark:bg-zinc-900` | `bg-base-100` or `bg-base-200` |
| `text-black` `dark:text-white` | `text-base-content` |
| `border-gray-300` | `border-base-300` |
| `bg-purple-600` | `btn-primary` |
| `text-gray-600` | `text-base-content opacity-70` |
| `bg-green-500` | `badge-success` |
| `bg-red-500` | `badge-error` |

## Testing

```javascript
// Browser console
document.documentElement.setAttribute('data-theme', 'light');
document.documentElement.setAttribute('data-theme', 'dark');
document.documentElement.setAttribute('data-theme', 'cupcake');
```

Test every component in all 7 themes before shipping.
