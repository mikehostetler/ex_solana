# Pod System

**Domain:** `JidoHub.Pods`  
**Tables:** pods, pod_memberships

## Resources & Relationships

### Pod
- `has_many :pod_memberships → PodMembership` (only for user-owned pods; filter pod.owner_type == :user)

### PodMembership
- `belongs_to :pod → Pod` (required)
- `belongs_to :user → User` (required)

## Actions

### Pod
- `create(name, description?, owner_type, owner_id)` - create
  - Changes: GenerateSlug, ValidateOwner
- `update(name?, description?, settings?)` - update
  - Changes: GenerateSlug
- `destroy` - destroy
- `by_slug(owner_type, owner_id, slug)` - read (get)
- `for_owner(owner_type, owner_id)` - read

### PodMembership (user-owned pods only)
- `create(pod_id, user_id, role?)` - sets joined_at
- `update(role?)` - update
- `destroy` - destroy
- defaults: read

## Data Model

### pods
- `id` uuid pk
- `name` string, required
- `slug` string /^[a-z0-9\-]+$/, required
- `description` string
- `owner_type` atom [:user, :organization], required
- `owner_id` uuid, required
- `settings` map, default %{}
- `metadata` map, default %{}
- identity unique_slug_per_owner(owner_type, owner_id, slug)
- timestamps

### pod_memberships
- `id` uuid pk
- `role` atom [:owner, :admin, :member], default :member
- `joined_at` utc_datetime_usec, required
- `pod_id` fk → pods, required
- `user_id` fk → users, required
- identity unique_membership(pod_id, user_id)
- timestamps

## Integrations

### Cross-Domain
- ValidateOwner reads Accounts.User or Organizations.Organization
- Authorization checks query Organizations for org-admin resolution

### Calculations
- `:full_path` → "@{owner.username|org.slug}/{pod.slug}"
- `:owner` → map of owner fields:
  - user: [:id, :email, :username]
  - org: [:id, :name, :slug]

## Constraints & Validations

### Slug
- Auto-generated via Changes.GenerateSlug
- Normalizes name, ensures owner-scoped uniqueness
- Excludes current id on update

### Owner Existence
- Changes.ValidateOwner verifies owner exists in Accounts or Organizations

### Policies

#### Pod
- **create:** Checks.CanCreatePod
  - user: actor.id == owner_id
  - organization: actor is org owner OR has membership role [:owner, :admin]
- **read:** allow all (current state)
- **update/destroy:**
  - user-owned: actor.id == owner_id
  - org-owned: Checks.IsOrgAdmin (org owner or membership role [:owner, :admin])

#### PodMembership
- **create:** Checks.ActorOwnsUserPod (custom check - actor owns user-type pod)
- **update/destroy:** expr(pod.owner_type == :user and pod.owner_id == ^actor(:id))
- **read:** relates_to_actor_via(:user) OR expr(pod.owner_type == :user and pod.owner_id == ^actor(:id))
- **validation:** Prevents creating memberships for org-owned pods (they use org memberships)
