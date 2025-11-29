# Layout System (Phoenix 1.8+)

## File Locations and Roles

**lib/jido_hub_web/components/layouts.ex**
- `JidoHubWeb.Layouts` module: embeds layouts/* templates and defines shared components
- `flash_group/1`: standardized flash renderer (info/error + client/server connectivity messages)
- `theme_toggle/1` and `theme_toggle_icon/1`: UI for switching themes

**lib/jido_hub_web/components/layouts/root.html.heex**
- Root layout template (HTML skeleton):
  - `<.live_title>` with default "JidoHub" and suffix " · Phoenix Framework"; uses `assigns[:page_title]`
  - CSRF meta tag
  - Pre-CSS inline theme script (prevents FOUC; reads `localStorage` key `jido_hub:theme` and sets `[data-theme]` on `<html>`)
  - Global stylesheet and JS includes with `phx-track-static`
  - `{@inner_content}` placeholder for rendered content layouts

**lib/jido_hub_web/components/layouts/public.html.heex**
- Public/marketing layout: navbar, content area, footer
- Used for: landing pages, feature pages, content marketing

**lib/jido_hub_web/components/layouts/auth.html.heex**
- Auth layout: minimal chrome, centered form container
- Used for: login, signup, password reset, magic link

**lib/jido_hub_web/components/layouts/dashboard.html.heex**
- Dashboard layout: drawer sidebar, topbar, main content
- Used for: authenticated app (workflows, settings)

## How LiveViews Use Layouts

Layouts are **assigned per `live_session` in the router**. LiveViews automatically render within the configured layout—no manual wrapping needed.

Set page title in LiveView mount/handle_event:

```elixir
assign(socket, :page_title, "Your Page Title")
```

The root layout renders it via:

```heex
<.live_title default="JidoHub" suffix=" · Phoenix Framework">
  {assigns[:page_title]}
</.live_title>
```

## Router Configuration

Assign layouts per `live_session`:

```elixir
# Public/marketing pages
live_session :public,
  layout: {JidoHubWeb.Layouts, :public} do
  live "/", HomeLive, :index
end

# Auth forms
live_session :auth,
  layout: {JidoHubWeb.Layouts, :auth} do
  live "/login", LoginLive, :index
  live "/signup", RegisterLive, :index
end

# Dashboard/app
live_session :app,
  layout: {JidoHubWeb.Layouts, :dashboard} do
  live "/workflows", WorkflowLive.Index, :index
end
```

## Layouts Module API

**Layouts.flash_group(assigns)**
- Required: `flash` (map)
- Optional: `id` (string, default `"flash-group"`)
- Renders `:info` and `:error` flashes and connection error banners using `phx-connected`/`phx-disconnected`

**Layouts.theme_toggle/1 and Layouts.theme_toggle_icon/1**
- Emit dropdown UIs with `data-set-theme` buttons
- Theme persistence: `localStorage` key `jido_hub:theme`
- Root layout preloads theme before CSS to avoid FOUC
- Add to nav/header as needed

## Layout Hierarchy

**root.html.heex (template)**
- Global HTML structure and assets
- Configured as the root layout via `:put_root_layout` plug
- Renders `{@inner_content}` which contains the content layout (public/auth/dashboard)

**Content layouts (public/auth/dashboard.html.heex)**
- Assigned per `live_session` in router
- Provide layout-specific chrome (nav, sidebar, footer)
- Render `{@inner_content}` which contains LiveView content
- Include `<.flash_group flash={@flash}/>` for messages

## Script/Style Patterns

**Global assets:**
- CSS: `/assets/css/app.css` (`phx-track-static`)
- JS: `/assets/js/app.js` (`defer`, `phx-track-static`)

**Head management:**
- Use `@page_title` for page title
- Edit `root.html.heex` for other global tags

**Theme:**
- Inline script in `root.html.heex` sets `data-theme` before CSS loads
- Only FOUC-critical logic belongs here
- Use `theme_toggle` components for UX
- Persist to `localStorage` (handled by `app.js` logic expecting `data-set-theme`)

## Conventions

- **Never** manually wrap LiveView content with layout components—use router `layout:` configuration
- Set `@page_title` in LiveViews to update the document title
- Keep `phx-track-static` on CSS/JS links in `root.html.heex`
- Put per-page JS in hooks within `app.js`; avoid adding non-critical inline scripts to `root.html.heex`
- Add new reusable chrome as function components in `Layouts` module (e.g., nav sections, user menu)
- Place layout-specific chrome (navbars, sidebars, footers) directly in layout templates

## Common Mistakes to Avoid

| Mistake | Solution |
|---------|----------|
| Manually wrapping LiveView content with `<Layouts.*>` | Layouts assigned via router `layout:` config |
| Not assigning `layout:` in `live_session` | Layout won't render; add `layout: {Layouts, :public}` etc. |
| Trying to change the head from a LiveView (except title) | Modify `root.html.heex` instead |
| Removing `phx-track-static` | Breaks cache invalidation and static tracking |
| Adding heavy inline scripts/styles to `root.html.heex` | Hurts performance and LiveView behavior |
| Creating new layout templates without router config | Template won't be used; must assign in `live_session` |

## Extending Layouts

- Create new layout templates in `lib/jido_hub_web/components/layouts/` (e.g., `admin.html.heex`)
- `embed_templates "layouts/*"` automatically generates functions for all templates
- Assign new layouts in router via `live_session :admin, layout: {Layouts, :admin}`
- For global changes (meta tags, additional global assets), edit `root.html.heex`
- Extract reusable chrome sections as function components in `Layouts` module
