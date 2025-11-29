# AGENTS REFERENCE

This folder contains the complete specification and design reference for JidoHub. Use these docs to understand requirements and implementation details.

## Quick Reference
- Stack: Phoenix LiveView, Ash Framework, AshAuthentication, DaisyUI, Alpine.js, Oban
- Multitenancy: attribute strategy on organization_id
- Domains: Accounts, Organizations, Pods, Notifications (planned)
- Auth: Ash.Policy.Authorizer; actor: Accounts.User
- UI: Slack-like 4-col layout; dark-first; DaisyUI tokens only

## Documentation Index

### Core Specifications (spec/)
- [ACCOUNTS_SPEC.md](spec/ACCOUNTS_SPEC.md) - Users, tokens, API keys, AshAuthentication strategies
- [ORGANIZATIONS_SPEC.md](spec/ORGANIZATIONS_SPEC.md) - Orgs, memberships, invitations, roles
- [PODS_SPEC.md](spec/PODS_SPEC.md) - Pods (user/org-owned), pod memberships, slugs
- [AUTHORIZATION_SPEC.md](spec/AUTHORIZATION_SPEC.md) - Ash policies, actor permissions, bypass rules
- [MISC_SPEC.md](spec/MISC_SPEC.md) - Slug service, seeds, repo config

### Design System (design/)
- [LAYOUTS.md](design/LAYOUTS.md) - 4-col shell, root/app layouts, component wrappers
- [THEME.md](design/THEME.md) - Alpine store, DaisyUI tokens, keyboard shortcuts

### Planning (plan/)
- [NOTIFY_PLAN.md](plan/NOTIFY_PLAN.md) - Notification system architecture (multitenancy, Oban, PubSub)

### Top-Level Docs
- [ROUTES.md](ROUTES.md) - Full routing patterns, slug resolution, reserved slugs
- [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) - DaisyUI + CoreComponents integration
- [FIRST_IMPRESSION.md](FIRST_IMPRESSION.md) - Landing page goals