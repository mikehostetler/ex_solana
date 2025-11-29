# Layout System

## Overview

JidoHub uses **DaisyUI components** for UI primitives and **Tailwind utilities** for layout, spacing, and responsive design. All layout is handled through Tailwind's flexbox, grid, and spacing utilities—never through custom CSS.

## Layout Shells

### Public/Auth Pages (`PageShell`)
- **Structure**: navbar → main → footer
- **Container**: `container mx-auto px-4` (or `px-6 lg:px-8` for wider screens)
- **Vertical rhythm**: `py-6` on main content
- **Usage**: Wrap all public-facing and auth pages

### Dashboard (`DashboardShell`)
- **Structure**: DaisyUI `drawer` with sidebar + navbar
- **Sidebar**: `w-64` fixed on lg+, collapsible drawer on mobile
- **Content area**: `flex-1 p-6 bg-base-100`
- **Borders**: Use `border-base-300` consistently

## Spacing Standards

| Context | Horizontal | Vertical |
|---------|-----------|----------|
| Page content | `px-4` (sm: `px-6`, lg: `px-8`) | `py-6` |
| Dashboard main | `p-6` | — |
| Drawers/Modals | `p-4` | — |
| Cards | `p-4` or `p-6` | — |

## Responsive Patterns

### Breakpoints (Tailwind)
- `sm`: 640px
- `md`: 768px
- `lg`: 1024px
- `xl`: 1280px

### Common patterns
```heex
<!-- Hide on mobile, show on desktop -->
<div class="hidden lg:flex">...</div>

<!-- Stack on mobile, row on desktop -->
<div class="flex flex-col lg:flex-row gap-4">...</div>

<!-- Responsive grid -->
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">...</div>
```

## DaisyUI Layout Components

### Navbar
```heex
<nav class="navbar bg-base-100 border-b border-base-300">
  <div class="navbar-start">...</div>
  <div class="navbar-center">...</div>
  <div class="navbar-end">...</div>
</nav>
```

### Drawer (Dashboard)
```heex
<div class="drawer lg:drawer-open">
  <input id="sidebar" type="checkbox" class="drawer-toggle" />
  <div class="drawer-content"><!-- main --></div>
  <div class="drawer-side"><!-- sidebar --></div>
</div>
```

### Footer
```heex
<footer class="footer footer-center p-10 bg-base-200">
  <aside>...</aside>
</footer>
```

## Best Practices

1. **Use `container mx-auto`** for page-level content (public/auth)
2. **Route through CoreComponents**: Prefer `<.page_shell>` or `<.dashboard_shell>` over raw markup
3. **Consistent borders**: Always use `border-base-300` (never raw colors)
4. **Spacing tokens**: Stick to `p-4`, `p-6`, `gap-2`, `gap-4` for consistency
5. **Rounded corners**: Use `rounded-box` (DaisyUI token) instead of `rounded-xl`
6. **Z-index**: Use Tailwind tokens (`z-10`, `z-50`) not arbitrary values (`z-[1]`)

## Common Mistakes

❌ **Don't**: `<div style="padding: 20px">`  
✅ **Do**: `<div class="p-5">`

❌ **Don't**: `<nav class="flex justify-between p-4 bg-gray-100">`  
✅ **Do**: `<nav class="navbar bg-base-100">`

❌ **Don't**: Custom CSS for layout in `.css` files  
✅ **Do**: Tailwind utilities in templates

## References

- [Tailwind Layout](https://tailwindcss.com/docs/flex-basis)
- [Tailwind Sizing](https://tailwindcss.com/docs/width)
- [Tailwind Flexbox](https://tailwindcss.com/docs/flex)
- [Tailwind Grid](https://tailwindcss.com/docs/grid-template-columns)
- [DaisyUI Navbar](https://daisyui.com/components/navbar/)
- [DaisyUI Drawer](https://daisyui.com/components/drawer/)
