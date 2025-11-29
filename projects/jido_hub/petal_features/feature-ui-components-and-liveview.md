# Feature: UI Components & LiveView

## Overview

The UI Components & LiveView feature provides a comprehensive design system built on Tailwind CSS, Phoenix LiveView, and modern component patterns. It delivers a cohesive set of reusable components including forms, tables, modals, toasts, and navigation elements that create consistent, responsive user interfaces. The system leverages Heroicons for iconography and follows modern web design principles with utility-first CSS and reactive LiveView updates.

This feature serves as the presentation layer foundation, enabling rapid UI development while maintaining design consistency across the application. It includes both server-rendered LiveView components and client-side asset compilation pipelines through esbuild and Tailwind, providing a complete front-end development environment.

## Key Capabilities

- Tailwind CSS-based utility-first styling with custom configuration
- Comprehensive component library (forms, tables, modals, toasts, navigation)
- Phoenix LiveView reactive components with real-time updates
- Heroicons and Lucide Icons integration for consistent iconography
- Asset compilation pipeline (esbuild, Tailwind) for optimized delivery
- Responsive design patterns and mobile-first layouts
- Content Security Policy integration for enhanced security
- Phoenix Storybook for component development and documentation

## Architecture & Implementation

### Related Modules

- `lib/jido_hub_web/components/` - Core component definitions
- `lib/jido_hub_web/live/` - LiveView modules and live components
- `lib/jido_hub_web/components/layouts/` - Application layout templates
- `assets/js/` - JavaScript hooks and client-side logic
- `assets/css/` - Tailwind configuration and custom styles
- `priv/static/` - Compiled assets and static resources

### Key Dependencies

- `phoenix_live_view` (~> 1.1.0) - Real-time interactive components
- `tailwind` (~> 0.3) - Utility-first CSS framework
- `heroicons` (v2.2.0) - SVG icon library
- `lucide_icons` (~> 2.0) - Additional icon library
- `esbuild` (~> 0.10) - JavaScript bundler
- `phoenix_html` (~> 4.1) - HTML generation helpers
- `phoenix_storybook` (~> 0.9.3) - Component development environment

## Integration Points

The UI Components & LiveView feature integrates deeply with Phoenix's routing and controller layers, serving as the presentation layer for all user-facing functionality. It connects with authentication flows through LiveView mounts and session management, and coordinates with the Ash Admin and monitoring dashboards for consistent UI/UX. The component system is designed to work seamlessly with form submissions, real-time updates via PubSub, and client-server communication through Phoenix Channels.

## Adaptation Notes

When extracting this feature into JidoHub, consider maintaining the existing component structure while customizing Tailwind themes and component variants to match JidoHub branding. The core LiveView components are framework-agnostic and can be adapted, but pay attention to dependencies on Petal Components if they exist in the original codebase. Asset compilation configuration in `mix.exs` and `config/` will need to be preserved. Consider creating a component style guide or Storybook instance specifically for JidoHub to document customizations and maintain design consistency across the platform.

## Gap Analysis: JidoHub vs Petal Pro

### Current JidoHub Implementation

**Component Library:**
- [core_components.ex](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/components/core_components.ex) - Basic Phoenix components (flash, button, input, table, modal, header, back, error, icon, simple_form, list)
- Custom layout components: dashboard_layout, dashboard_nav, sidebar_components, bottom_drawer, icon_panel, icon_rail, left_nav, sidebar_nav, workspace_nav
- One UI component: [command_palette.ex](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/components/ui/command_palette.ex)
- Dashboard-specific components: header, left_nav, top_nav, right_sidebar, bottom_console

**Styling & Theming:**
- Tailwind CSS v4 with custom configuration
- DaisyUI plugin for component primitives (vendored)
- Multiple themes enabled: light, dark, cupcake, wireframe, business, nord
- Custom theme overrides in [assets/css/themes/](file:///Users/mhostetler/Source/Jido/hub/jido_hub/assets/css/themes)
- Dedicated CSS files: app.css, dashboard.css, admin.css, typography.css
- Heroicons integration via vendor plugin

**LiveView Implementation:**
- Basic LiveViews: login, register, dashboard, profile, settings (profile/preferences/security)
- Admin dashboard (minimal placeholder)
- Workflow views
- No LiveComponents for reusable UI elements

### Missing from JidoHub

**Petal Pro Component Library:**
1. **pro_components/** - Advanced component collection:
   - aurora.ex - Animated visual effects
   - auth_layout.ex - Dedicated auth page layouts
   - border_beam.ex - Decorative border animations
   - color_scheme_switch.ex - Theme switching UI
   - combo_box.ex - Advanced combobox component
   - content_editor.ex - Rich text editor
   - flash.ex - Enhanced flash messages
   - floating_div.ex - Floating UI elements
   - language_select.ex - I18n language selector
   - local_time.ex - Timezone-aware time display
   - markdown.ex - Markdown rendering component
   - navbar.ex - Full-featured navigation bar
   - sidebar_layout.ex - Sidebar layout system
   - sidebar_menu.ex - Sidebar navigation menu
   - stacked_layout.ex - Stacked layout pattern
   - user_dropdown_menu.ex - User account dropdown
   - data_table/ - Full data table implementation

2. **Specialized Component Modules:**
   - alpine_components.ex - Alpine.js integrated components
   - billing_components.ex - Stripe billing UI components
   - email_components.ex - Transactional email templates
   - file_upload_components.ex - File upload with progress
   - landing_page_components.ex - Marketing page components

3. **Advanced Features:**
   - Route tree component for navigation visualization
   - Social authentication buttons
   - Page header/breadcrumb components
   - Advanced form components with validation UI
   - Multi-step forms/wizards
   - Empty states and skeleton loaders

### Implementation Priority

**HIGH Priority:**
1. **color_scheme_switch.ex** - Critical for theme switching UX (JidoHub has theming but no UI control)
2. **user_dropdown_menu.ex** - Standard UX pattern missing from JidoHub nav
3. **sidebar_menu.ex** - JidoHub has custom sidebar_nav but could benefit from standardized menu component
4. **data_table/** - Essential for admin and data-heavy pages (current implementation uses basic table component)
5. **flash.ex** - Enhanced flash messages beyond basic Phoenix implementation

**MEDIUM Priority:**
1. **navbar.ex** - JidoHub has custom nav components but standardized navbar would improve consistency
2. **markdown.ex** - Useful for documentation and user-generated content
3. **local_time.ex** - Important for multi-timezone user base
4. **combo_box.ex** - Better UX than select dropdowns for searchable lists
5. **empty states & skeleton loaders** - Improves perceived performance
6. **auth_layout.ex** - JidoHub uses generic layouts for auth pages

**LOW Priority:**
1. **content_editor.ex** - Rich text editing (needed only if user content creation is core feature)
2. **file_upload_components.ex** - Needed only when file uploads are implemented
3. **aurora.ex, border_beam.ex, floating_div.ex** - Visual polish/marketing elements
4. **landing_page_components.ex** - Marketing-focused, not core app functionality
5. **billing_components.ex** - Only needed if implementing Stripe billing
6. **social_button.ex** - Only needed if adding OAuth providers
7. **alpine_components.ex** - Only if Alpine.js integration is desired

### Migration Complexity

**SIMPLE (1-2 hours each):**
- color_scheme_switch.ex - Straightforward theme toggle component
- user_dropdown_menu.ex - Standard dropdown pattern
- local_time.ex - Wrapper around timezone library
- social_button.ex - Basic styled buttons

**MODERATE (4-8 hours each):**
- sidebar_menu.ex - Requires integration with existing navigation structure
- navbar.ex - Needs coordination with layout system
- flash.ex - Extends existing flash system
- combo_box.ex - Complex interaction patterns
- markdown.ex - Requires markdown library integration
- auth_layout.ex - Needs auth flow coordination

**COMPLEX (1-3 days each):**
- data_table/ - Full-featured tables with sorting, filtering, pagination, selection
- content_editor.ex - Rich text editor requires significant JS integration
- file_upload_components.ex - Needs backend file handling, progress tracking, S3/storage integration

**Migration Strategy:**
1. Start with color_scheme_switch and user_dropdown_menu (quick wins, visible UX improvements)
2. Implement data_table if admin/data management features are priority
3. Add navbar and sidebar_menu to standardize navigation patterns
4. Implement markdown, local_time, combo_box as needed features arise
5. Defer visual polish components (aurora, border_beam) until core functionality is complete
6. Only implement billing/file upload components when those features are on the roadmap
