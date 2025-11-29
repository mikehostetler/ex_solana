# Misc Systems

## Repo

**Module:** `JidoHub.Repo` (AshPostgres.Repo)

- otp_app: :jido_hub
- installed_extensions: ["ash-functions", "citext"]
- prefer_transaction?: false
- min_pg_version: 14.17.0

## Mailer

**Module:** `JidoHub.Mailer` (Swoosh.Mailer)

- otp_app: :jido_hub
- Used by authentication email senders:
  - SendMagicLinkEmail
  - SendPasswordResetEmail
  - SendNewUserConfirmationEmail
- URLs built via Phoenix.VerifiedRoutes.unverified_url(JidoHubWeb.Endpoint, ...)

## Secrets Management

**Module:** `JidoHub.Secrets` (AshAuthentication.Secret)

- `secret_for [:authentication, :tokens, :signing_secret], User`
- Fetches Application.fetch_env(:jido_hub, :token_signing_secret)
- Requires runtime config: `config :jido_hub, :token_signing_secret`

## Slug Resolution Service

**Module:** `JidoHub.Slugs`

### Reserved Slugs
Built-in list: login, signup, settings, admin, dashboard, etc.

### Functions

#### `resolve(slug, opts \\ [])`
Returns: `{:ok, {:user | :org | :pod, record}} | {:error, :not_found}`

Priority:
1. User (username)
2. Organization (slug)
3. Pod alias (not implemented)

Options:
- `check_pod_alias?` (default false)
- `actor` (unused in lookups)

#### `resolve_owner_and_pod(owner_slug, pod_slug, opts \\ [])`
Returns: `{:ok, %{owner: {:user | :org, record}, pod: record}} | {:error, :not_found}`

#### `reserved?(slug)`
Returns: boolean

### Implementation Notes
- Uses Ash reads without authorization
- Queries Users by username (Accounts)
- Queries Orgs by slug (Organizations)
- Queries Pods by owner_type/owner_id/slug (Pods)

## Notable Constraints

- Email routes use "unverified_url" to dynamic AshAuthentication paths
- Invitation unique_pending_invitation identity is logical (where-clause)
- Postgres unique index skipped (skip_unique_indexes) in resource config
- Many changes/query checks bypass authorization (authorize?: false) for internal validation
- Policy gates handled at action level
