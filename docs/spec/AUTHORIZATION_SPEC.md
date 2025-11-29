# Authorization Architecture

**Framework:** Ash Policy Authorizer  
**Actor Type:** `JidoHub.Accounts.User`

## Global Patterns

### Policy Engine
- All resources use `authorizers: [Ash.Policy.Authorizer]`
- Actor is expected to be a `JidoHub.Accounts.User` struct
- Most checks compare `actor.id`

### Common Predicates
- `authorize_if always()` - explicit public actions
- `authorize_if actor_present()` - requires logged-in user
- `authorize_if relates_to_actor_via(...)` - declarative relationship traversal
- `authorize_if expr(...)` - direct field/actor comparisons
- `bypass ... authorize_if always()` - internal flows (auth, token-based)

### Cross-Resource Patterns
- Permission checks often query with `authorize?: false` to avoid recursion
- Only validates existence/role using IDs
- Safe for non-sensitive data checks

## Authentication Resources

### User, Token, ApiKey
**Policy:** `bypass AshAuthentication.Checks.AshAuthenticationInteraction authorize_if always()`

**Implication:** Only AshAuthentication flows interact with these resources by policy.

## Organization-Level Authorization

### Organization

#### Read
- `authorize_if relates_to_actor_via(:owner)` - org owner
- `authorize_if relates_to_actor_via([:memberships, :user])` - any org member

#### Create
- `authorize_if actor_present()` - any authenticated user can create
- ✅ **Fixed:** Uses `relate_actor(:owner)` to set `owner_id = actor.id` automatically

#### Update/Destroy
- `authorize_if relates_to_actor_via(:owner)` - org owner only

#### transfer_ownership
- `authorize_if relates_to_actor_via(:owner)` - org owner only

### Membership

#### Create (regular)
- `authorize_if Checks.CanManageMemberships` - custom check ensures actor is org owner/admin
- ✅ **Fixed:** Only org owners and admins can create memberships

#### Create (via invite)
- `bypass action(:create_via_invite) authorize_if always()` - internal action for invitation acceptance
- ✅ **Secure:** Only called by `AcceptInvitation` change after validating:
  - Token validity and expiration
  - Email match between invitation and accepting user
  - User not already a member
  - All parameters (org_id, user_id, role) derived from validated invitation

#### Update/Destroy
- `authorize_if relates_to_actor_via([:organization, :owner])` - org owner
- `authorize_if expr(exists(organization.memberships, user_id == ^actor(:id) and role in [:admin, :owner]))` - org admins/owners

#### Read
- `authorize_if relates_to_actor_via(:user)` - user's own membership
- `authorize_if relates_to_actor_via([:organization, :owner])` - org owner sees all
- `authorize_if relates_to_actor_via([:organization, :memberships, :user])` - any org member

### Organization Roles

#### Owner
- Set via `Organization.owner_id` relationship
- Full control: read/update/destroy/transfer_ownership
- Can manage memberships and invitations

#### Admin
- Via `Membership` with `role: :admin`
- Can manage memberships and invitations
- Cannot update/destroy the Organization itself
- Can read organization and memberships

#### Member
- Via `Membership` with `role: :member`
- Can read organization and its memberships
- Cannot manage organization or memberships

### Invitations

#### Bypass
- `bypass action(:accept) authorize_if always()` - token-based acceptance
- `bypass action(:by_token) authorize_if always()` - token-based lookup

#### Create
- Policy: `authorize_if actor_present()` - requires logged-in user
- Change `ValidateInvitationPermissions` enforces:
  - `invited_by_id` must equal `actor.id`
  - Actor must be org owner or admin
  - Uses `authorize?: false` reads

#### Read/Update/Destroy
- `authorize_if relates_to_actor_via([:organization, :owner])` - org owner
- `authorize_if expr(organization.memberships.user_id == ^actor(:id) and organization.memberships.role in [:admin, :owner])` - org admins/owners

## Pod-Level Authorization

### Pod

#### Ownership Model
- `owner_type`: `:user` or `:organization`
- `owner_id`: UUID of user or organization

#### Create
- `authorize_if Checks.CanCreatePod`
  - **User pods:** `owner_id == actor.id`
  - **Org pods:** actor is org owner OR has admin/owner membership

#### Read
- `authorize_if always()` - pods are globally readable (public)

#### Update/Destroy
- `authorize_if expr(owner_type == :user and owner_id == ^actor(:id))` - user owner
- `authorize_if Checks.IsOrgAdmin` - org owner or org admin

### PodMembership (user-owned pods only)

**Scope:** Only for user-owned pods; org-owned pods use Organization memberships.

#### Create
- `authorize_if Checks.ActorOwnsUserPod` - custom check verifies actor owns user-type pod
- Additional validation prevents creating memberships for org-owned pods

#### Update/Destroy
- `authorize_if expr(pod.owner_type == :user and pod.owner_id == ^actor(:id))` - only pod owner

#### Read
- `authorize_if relates_to_actor_via(:user)` - user's own membership
- `authorize_if expr(pod.owner_type == :user and pod.owner_id == ^actor(:id))` - pod owners
- ✅ **Fixed:** Properly scoped to prevent unauthorized reads

## Custom Policy Checks

### `JidoHub.Pods.Pod.Checks.CanCreatePod`
**Purpose:** Gate Pod.create

**Logic:**
- User-owned: `actor.id == owner_id`
- Org-owned: actor is org owner OR has membership role `[:owner, :admin]`
- Uses `authorize?: false` lookups

### `JidoHub.Pods.Pod.Checks.IsOrgAdmin`
**Purpose:** Determine if actor can manage org-owned pods

**Logic:**
- Actor is `org.owner` OR
- Has `Organizations.Membership` role `[:owner, :admin]`
- Uses `authorize?: false` reads

### `JidoHub.Pods.PodMembership.Checks.ActorOwnsUserPod`
**Purpose:** Allow pod owners to create PodMemberships (replaces deprecated IsPodOwner)

**Logic:**
- Changeset context: verifies `pod.owner_type == :user and pod.owner_id == actor.id`
- Query context: checks specific resource's pod ownership
- ✅ **Secure:** No global access granted for bulk queries

### `JidoHub.Organizations.Membership.Checks.CanManageMemberships`
**Purpose:** Check if actor can create memberships in an organization

**Logic:**
- Actor is organization owner (via `owner_id` match) OR
- Actor has existing membership with role `[:admin, :owner]`
- Uses `authorize?: false` lookups to avoid recursion

### `JidoHub.Organizations.Membership.Checks.ActorIsAdminOrOwner`
**Purpose:** Check if actor is admin/owner in membership's organization

**Note:** Not currently referenced by active policies; uses direct Ecto queries.

## Permission Matrix

### Organizations

| Role | Read | Create | Update | Destroy | Transfer | Manage Members | Manage Invites |
|------|------|--------|--------|---------|----------|----------------|----------------|
| Owner | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Admin | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ |
| Member | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Authenticated | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Anonymous | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |

### Pods (User-Owned)

| Role | Read | Create | Update | Destroy | Manage Members |
|------|------|--------|--------|---------|----------------|
| Owner | ✓ | ✓ | ✓ | ✓ | ✓ |
| Member | ✓* | ✗ | ✗ | ✗ | ✗ |
| Anyone | ✓ | ✗ | ✗ | ✗ | ✗ |

*\* Member can read own PodMembership only*

### Pods (Organization-Owned)

| Role | Read | Create | Update | Destroy |
|------|------|--------|---------|---------|
| Org Owner | ✓ | ✓ | ✓ | ✓ |
| Org Admin | ✓ | ✓ | ✓ | ✓ |
| Org Member | ✓ | ✗ | ✗ | ✗ |
| Anyone | ✓ | ✗ | ✗ | ✗ |

## Security Status

### ✅ Fixed Issues

#### PodMembership Read Exposure
**Status:** ✅ **FIXED**

**Solution Implemented:**
- Replaced buggy `IsPodOwner` check with secure expr-based policies
- Created `ActorOwnsUserPod` custom check for create actions
- Added validation to prevent org-owned pods from having PodMemberships
- All tests passing with new authorization tests added

#### Membership.create Authorization
**Status:** ✅ **FIXED**

**Solution Implemented:**
- Replaced open `authorize_if always()` with `CanManageMemberships` custom check
- Now enforces that only org owners and admins can create memberships
- Separate `create_via_invite` action for invitation acceptance flow

#### Organization.create Owner Assignment
**Status:** ✅ **FIXED**

**Solution Implemented:**
- Replaced manual `owner_id` argument with `relate_actor(:owner)` change
- `owner_id` is now automatically set to `actor.id`
- Policy changed from `always()` to `actor_present()` for safety

### Low Priority (Intentional?)

#### Public Pod.read
**Issue:** All pods globally readable; may expose metadata.

**Consideration:** If sensitive, add visibility attribute or relationship checks.

## Future Enhancements
1. Centralize role resolution logic
2. Add pod visibility controls
3. Consolidate duplicate admin/owner checks
4. Consider auditable policy filters
