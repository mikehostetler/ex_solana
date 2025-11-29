# Organization System

**Domain:** `JidoHub.Organizations`  
**Tables:** organizations, memberships, invitations

## Resources & Relationships

### Organization
- `belongs_to :owner → User` (required)
- `has_many :memberships → Membership`
- `many_to_many :members → User` (through memberships)

### Membership
- `belongs_to :user → User` (required)
- `belongs_to :organization → Organization` (required)

### Invitation
- `belongs_to :organization → Organization` (required)
- `belongs_to :invited_by → User` (required)

## Actions

### Organization
- `create(name?, description?, settings?, owner_id)` - create
- `update(name?, description?, settings?)` - update
- `transfer_ownership(new_owner_id)` - update
- defaults: read, destroy

### Membership
- `create(user_id, organization_id, role?)` - sets joined_at
- `update_role(role?)` - update
- defaults: read, destroy

### Invitation
- `create(email, role?, organization_id, invited_by_id)` - create
- `accept(token, accepting_user_id)` - update
- `resend()` - update
- `destroy` - destroy
- `by_token(token)` - read (get)

## Data Model

### organizations
- `id` uuid pk
- `name` string [1..255], required
- `slug` string /^[a-z0-9\-]+$/, required, identity unique_slug
- `description` string [<=1000]
- `settings` map, default %{}
- `owner_id` fk → users, required
- timestamps

### memberships
- `id` uuid pk
- `role` atom [:owner, :admin, :member], default :member
- `joined_at` utc_datetime, required
- `user_id` fk → users, required
- `organization_id` fk → organizations, required
- identity unique_user_organization(user_id, organization_id)
- timestamps

### invitations
- `id` uuid pk
- `email` ci_string (email regex), required
- `role` atom [:admin, :member], default :member
- `token` string, required, sensitive, identity unique_token
- `expires_at` utc_datetime, required
- `accepted_at` utc_datetime | nil
- `organization_id` fk → organizations, required
- `invited_by_id` fk → users, required
- identity unique_pending_invitation(email, organization_id) with where is_nil(accepted_at) and expires_at > now()
- Postgres skip_unique_indexes: [:unique_pending_invitation]

## Integrations

### Cross-Domain
- Invitation validation queries Organization and Membership without authorization
- Membership creation on acceptance uses after_action hook
- Organization slugs used in pod paths and Slugs service

## Constraints & Validations

### Organization
- **Slug:** auto-generated via Changes.GenerateSlug on create/update
- **Policies:**
  - read: owner or org member
  - create: allow anyone (ownership via owner_id arg)
  - update/destroy/transfer_ownership: owner only

### Membership
- **Policies:**
  - create: allow (validated at app level)
  - update/destroy: owner or org admin/owner
  - read: user, org owner, or org members

### Invitation
- **Create Changes:**
  - ValidateInvitationPermissions: invited_by == actor, actor is org owner/admin
  - GenerateToken: random 32-char URL-safe
  - SetExpiration: default 7 days (configurable)
  - PreventDuplicatePendingInvitation: no active duplicates per (email, org)
- **Accept Changes:**
  - Token match, not expired, not previously accepted
  - Accepting user email must match invitation email (case-insensitive)
  - User not already org member
  - Sets accepted_at, creates membership with invitation role
- **Policies:**
  - bypass for accept and by_token (token-gated)
  - create requires actor_present (permission via change)
  - read/update/destroy require org owner or org admin/owner
