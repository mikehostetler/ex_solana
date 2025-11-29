# Typography System

## Overview

JidoHub uses a **Linear-inspired typography scale** with custom utility classes that remain consistent across DaisyUI themes. All text styling uses these semantic classes—never inline font properties.

## Typography Scale

| Class | Use Case | Size | Weight | Line Height |
|-------|----------|------|--------|-------------|
| `.text-page-title` | Page titles | 18px (→20px md+) | 600 | 1.4 |
| `.text-section-header` | Section headers | 16px (→18px md+) | 600 | 1.5 |
| `.text-subsection-header` | Subsection headers | 14px | 600 | 1.5 |
| `.text-body` | Body text | 14px | 400 | 1.5 |
| `.text-body-medium` | Emphasized body | 14px | 500 | 1.5 |
| `.text-meta` | Metadata, timestamps | 13px | 400 | 1.5 |
| `.text-meta-medium` | Important metadata | 13px | 500 | 1.5 |
| `.text-label` | Labels, tags | 12px | 500 | 1.4 |

## Component Helpers (CoreComponents)

Route typography through semantic component functions instead of class strings:

```heex
<.page_title>Dashboard</.page_title>
<.section_header>Recent Activity</.section_header>
```

Defined in `CoreComponents`:
```elixir
def page_title(assigns), do: ~H"<h1 class='text-page-title'>{render_slot(@inner_block)}</h1>"
def section_header(assigns), do: ~H"<h2 class='text-section-header'>{render_slot(@inner_block)}</h2>"
```

## Best Practices

1. **Use semantic classes** over Tailwind font utilities (`text-xl`, `font-bold`)
2. **Prefer component helpers** over raw class strings
3. **Don't override** in templates—adjust `typography.css` if needed
4. **Responsive sizing** built-in for page-title and section-header at `md:` breakpoint
5. **Letter spacing** tuned for each level (negative on headers, neutral on body)

## DaisyUI + Typography Plugin

For **long-form content** (docs, markdown), use the Tailwind Typography plugin:

```heex
<article class="prose prose-sm md:prose-base">
  {@markdown_content}
</article>
```

DaisyUI themes automatically style `.prose` with theme colors via CSS variables.

**Never mix `.prose` with app UI**—it's for content-heavy pages only.

## Color & Theme

Typography classes use **DaisyUI theme tokens**:
- Body text: `text-base-content`
- Muted text: `text-base-content/70` or `text-base-300`
- Headings: inherit `text-base-content`

Always use DaisyUI color utilities (`text-*`) instead of raw Tailwind colors so themes work correctly.

## Common Patterns

### Page header
```heex
<header class="mb-6">
  <.page_title>Settings</.page_title>
  <p class="text-meta text-base-content/70 mt-1">Manage your account preferences</p>
</header>
```

### Card title
```heex
<div class="card">
  <div class="card-body">
    <h3 class="text-section-header">Card Title</h3>
    <p class="text-body">Card description text</p>
  </div>
</div>
```

### Data label + value
```heex
<div>
  <span class="text-label text-base-content/70">Status</span>
  <span class="text-body-medium">Active</span>
</div>
```

### Table headers
```heex
<table class="table">
  <thead>
    <tr>
      <th class="text-meta-medium">Name</th>
      <th class="text-meta-medium">Status</th>
    </tr>
  </thead>
</table>
```
_Note: `typography.css` already styles `table thead th` with 600 weight and 13px._

## Common Mistakes

❌ **Don't**: `<h1 class="text-xl font-bold">Title</h1>`  
✅ **Do**: `<.page_title>Title</.page_title>`

❌ **Don't**: `<p class="text-sm font-medium">Label</p>`  
✅ **Do**: `<span class="text-label">Label</span>`

❌ **Don't**: `<div style="font-size: 14px">Text</div>`  
✅ **Do**: `<p class="text-body">Text</p>`

❌ **Don't**: Mixing `.prose` in dashboard UI  
✅ **Do**: Use `.prose` only for markdown/docs pages

## Responsive Typography

Scale automatically adjusts on larger screens:
- `.text-page-title`: 18px → 20px at `md:`
- `.text-section-header`: 16px → 18px at `md:`

For custom responsive sizing:
```css
@media (min-width: 768px) {
  .text-page-title { font-size: 20px; }
}
```

## Extending the Scale

To add a new level, edit `assets/css/typography.css`:

```css
.text-hero {
  font-size: 24px;
  font-weight: 700;
  line-height: 1.2;
  letter-spacing: -0.02em;
}
```

Then add a helper in `CoreComponents`:
```elixir
def hero_title(assigns), do: ~H"<h1 class='text-hero'>{render_slot(@inner_block)}</h1>"
```

## References

- [Tailwind Typography Plugin](https://github.com/tailwindlabs/tailwindcss-typography)
- [DaisyUI Colors](https://daisyui.com/docs/colors/)
- [DaisyUI Themes](https://daisyui.com/docs/themes/)
