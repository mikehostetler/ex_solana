# Routing Patterns

This document establishes the canonical routing patterns for JidoHub.

## Core Principles

1. **Simple root route**: `/` serves landing page, redirects to `/dashboard` when logged in
2. **Simple authentication routes**: `/login`, `/signup`, `/reset`, `/confirm`
3. **Pod-centric routing**: `/:user_or_org_slug/:pod_slug` for all pod views
4. **Namespaced settings**: Personal settings under `/settings/*`, pod settings under pod routes
5. **RESTful conventions**: Plural for collections, singular for resources

## Route Structure

### Public Routes
```
/                   → Landing page (redirects to /dashboard when logged in)
/dashboard          → User dashboard (authenticated)
/login              → Sign in
/signup             → Account creation
/reset              → Password recovery
/confirm            → Email confirmation (token-based)
/privacy            → Privacy policy
/terms              → Terms of service
```

### Personal Settings Routes
```
/settings           → Personal settings hub
/settings/profile   → Profile settings
/settings/account   → Account settings
/settings/security  → Security & authentication
/settings/billing   → Billing & subscription
```

### Pod Routes

The core routing pattern follows `/:user_or_org_slug/:pod_slug`:

```
/:user_or_org_slug/:pod_slug          → Pod dashboard/main view
/:user_or_org_slug/:pod_slug/settings → Pod settings (owner/admin only)
```

**Examples:**
- `/alice/my-workflow` - Alice's personal pod
- `/acme-corp/production-pipeline` - Acme Corp organization's pod
- `/alice/my-workflow/settings` - Settings for Alice's pod
- `/acme-corp/production-pipeline/settings` - Settings for Acme's pod

## Implementation Notes

### Root Route Redirect

```elixir
# router.ex
live "/", HomeLive, :index
live "/dashboard", DashboardLive, :index

# In HomeLive.mount/3
def mount(_params, _session, socket) do
  if socket.assigns[:current_user] do
    {:ok, push_navigate(socket, to: ~p"/dashboard")}
  else
    {:ok, socket}
  end
end
```

### Pod Slug Resolution

The `/:user_or_org_slug/:pod_slug` route must resolve both slugs:

1. **First slug resolution**: Check if slug matches a user or organization
2. **Second slug resolution**: Find pod owned by that user/org
3. **Authorization**: Verify current user can access the pod

```elixir
# router.ex
live "/:user_or_org_slug/:pod_slug", PodLive, :show
live "/:user_or_org_slug/:pod_slug/settings", PodLive, :settings

# In PodLive.mount/3
def mount(%{"user_or_org_slug" => owner_slug, "pod_slug" => pod_slug}, _session, socket) do
  # 1. Resolve owner (user or org)
  owner = resolve_owner(owner_slug)
  
  # 2. Find pod by slug within owner's scope
  pod = Pods.get_pod_by_slug!(pod_slug, owner)
  
  # 3. Check authorization via Ash policies
  socket
  |> assign(:owner, owner)
  |> assign(:pod, pod)
end
```

### Reserved Slugs

To prevent conflicts with top-level routes, reserve these slugs:
- `dashboard`
- `settings`
- `login`
- `signup`
- `reset`
- `confirm`
- `logout`
- `privacy`
- `terms`
- `admin`
- `api`
- `auth`
- `dev`

These cannot be used as user or organization slugs.
