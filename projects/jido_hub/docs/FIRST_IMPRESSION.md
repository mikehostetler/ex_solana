# First Impression Experience

This document outlines the first-time developer experience for JidoHub.

## Overview

When a developer clones JidoHub, runs `mix setup`, and starts the server with `mix phx.server`, they should encounter a polished, informative landing page that:

1. Explains what JidoHub is and what it does
2. Provides clear paths to Sign In / Sign Up
3. Uses the same visual design system as the rest of the application
4. Includes sensible initial data for exploration

## Developer Journey

```
git clone <repo>
  ↓
mix setup
  ↓
mix phx.server
  ↓
Visit localhost:4000
  ↓
See polished landing page
  ↓
Sign in with test credentials
  ↓
Explore workflows in "agentjido" org
```

## Initial Data Setup

### Seeds (`priv/repo/seeds.exs`)

The `mix setup` command runs `mix ecto.setup`, which includes seeding. Seeds should create:

**Test Users:**
- alice@example.com (password: password123)
- bob@example.com (password: password123)
- charlie@example.com (password: password123)

**Default Organization:**
- Name: "AgentJido"
- Slug: "agentjido"
- Owner: alice@example.com
- Description: "Default organization for local development"

**Organization Memberships:**
- alice: owner
- bob: member
- charlie: member

**Implementation Requirements:**
- Seeds must be idempotent (can run multiple times safely)
- Use Ash domains and resources consistently
- Set `authorize?: false` for seed operations
- Provide helpful console output showing what was created

## Landing Page Design

### Visual Style

The landing page should match the `/workflows` design system:

**Typography Classes:**
- `.text-page-title` - Main headings (18px, font-weight: 600)
- `.text-subsection-header` - Section headers (14px, font-weight: 600)
- `.text-body` - Body text (14px, font-weight: 400)
- `.text-meta` - Metadata/hints (13px, font-weight: 400)

**Components:**
- Use `<.card>` from CoreComponents with borders: `card bg-base-200 border border-base-300/40 rounded-md shadow-sm`
- Use `<.button>` with variants (ghost, secondary, primary)
- Use DaisyUI utilities (divider, link)
- Use hero icons via `<.icon>`

**Layout:**
- Simple container layout (no DashboardLayout for logged-out users)
- Responsive grid for cards
- Top navbar with logo and auth actions

### Content Structure

**Navigation Bar:**
- JidoHub logo with rocket icon
- "Sign In" button (ghost variant)
- "Get Started" button (primary)

**Main Content Area:**

1. **Hero Section**
   - Page title: "JidoHub"
   - Subtitle: Brief description of the platform
   - Typography: text-page-title, text-body with opacity

2. **Feature Card** (2-column span)
   - "What is JidoHub?"
   - Description of platform capabilities
   - Bulleted list of key features
   - CTA buttons: "Get Started" and "Sign In"

3. **Quick Links Card** (1-column)
   - Links to GitHub, documentation
   - Divider
   - Full-width Sign In / Sign Up buttons

4. **Local Dev Setup Card** (3-column span)
   - Explain the seeded data
   - List test user credentials
   - Note about the agentjido organization

### Key Messages

**What is JidoHub?**
> A developer-focused platform to build, deploy, and manage automated workflows.

**Key Features:**
- Consistent dashboard layout and components
- Build and manage workflows from a unified UI
- Developer-first ergonomics and clear system primitives

**Local Dev Note:**
> On first install, we create a default organization "agentjido" and seed sample users. Sign in to start building workflows.

## Implementation Checklist

### Phase 1: Seeds
- [ ] Add helper function to read user by email
- [ ] Create "AgentJido" organization with alice as owner
- [ ] Add organization memberships for bob and charlie
- [ ] Test idempotent behavior (run seeds multiple times)
- [ ] Verify console output is helpful

### Phase 2: Landing Page
- [ ] Update `landing_page/1` in `lib/jido_hub_web/live/home_live.ex`
- [ ] Use proper typography classes throughout
- [ ] Implement card-based layout matching workflows page
- [ ] Add navigation bar with auth actions
- [ ] Include feature descriptions and quick links
- [ ] Add local dev setup information
- [ ] Test responsive behavior
- [ ] Verify all links work correctly

### Phase 3: Verification
- [ ] Fresh clone of repo
- [ ] Run `mix setup` and verify seeds run cleanly
- [ ] Start server with `mix phx.server`
- [ ] Visit localhost:4000 and verify landing page
- [ ] Sign in with test credentials
- [ ] Verify "agentjido" organization exists and is accessible
- [ ] Check visual consistency with /workflows page

## Design Decisions

### Why Not Use DashboardLayout for Landing?

The DashboardLayout component includes left sidebar, right panel, and bottom console - all designed for authenticated workflow management. For a logged-out landing page:

- Simpler is better for first impression
- Avoid auth-dependent components
- Reduce complexity and dependencies
- Keep focus on getting started

### Why "agentjido"?

- Long-running reference organization name
- Provides immediate context for exploration
- Gives users something to interact with immediately
- Demonstrates multi-user organization features

### Why Seed Multiple Users?

- Demonstrates multi-user capabilities immediately
- Allows testing of permissions and roles
- Provides realistic data for exploration
- Makes the platform feel "alive" from first run

## Future Enhancements

- **Onboarding Flow:** Step-by-step wizard for first-time users
- **Sample Workflows:** Pre-built workflow templates in agentjido org
- **Documentation Links:** Context-sensitive help throughout
- **Video Walkthrough:** Embedded demo of key features
- **Multi-tenant Onboarding:** Auto-create personal org on signup
