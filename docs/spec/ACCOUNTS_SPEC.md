# Account System

**Domain:** `JidoHub.Accounts`  
**Tables:** users, tokens, api_keys

## Resources & Relationships

### User
- `has_many :valid_api_keys → ApiKey` (filter: valid)
- `has_many :owned_organizations → Organization` (owner_id)
- `has_many :memberships → Membership`
- `many_to_many :organizations → Organization` (through memberships)
- `has_many :sent_invitations → Invitation` (invited_by_id)

### ApiKey
- `belongs_to :user → User`

### Token
- AshAuthentication.TokenResource

## Actions

### User
- `get_by_subject(subject)` - read
- `change_password(current_password, password, password_confirmation)` - update
- `sign_in_with_password(email, password)` - read → token metadata
- `sign_in_with_token(token)` - read → token metadata
- `register_with_password(email, username, password, password_confirmation)` - create → token metadata
- `request_password_reset_token(email)` - action
- `get_by_email(email)` - read
- `get_by_username(username)` - read
- `reset_password_with_token(reset_token, password, password_confirmation)` - update → token
- `sign_in_with_magic_link(token, username?)` - create → token metadata
- `request_magic_link(email)` - action
- `sign_in_with_api_key(api_key)` - read

### ApiKey
- `create(user_id, expires_at)` - generates key + hash (prefix: jidohub)
- defaults: read, destroy

### Token
- `expired` - read
- `get_token(token?|jti?, purpose?)` - read
- `revoked?(token?|jti?)` - action → boolean
- `revoke_token(token)` - create
- `revoke_jti(subject, jti)` - create
- `store_token(token, purpose, extra_data?)` - create
- `expunge_expired` - destroy
- `revoke_all_stored_for_subject(subject)` - update

## Data Model

### users
- `id` uuid pk
- `email` ci_string, required, public, identity unique_email
- `username` string [4..30], required, public, identity unique_username
- `hashed_password` string, sensitive
- `confirmed_at` utc_datetime_usec
- timestamps

### api_keys
- `id` uuid pk
- `api_key_hash` binary, required, sensitive, identity unique_api_key
- `expires_at` utc_datetime_usec, required
- `user_id` fk → users
- `valid` calc (expires_at > now())

### tokens
- `jti` string pk, sensitive
- `subject` string, required
- `expires_at` utc_datetime, required
- `purpose` string, required
- `extra_data` map
- created_at, updated_at

## Integrations

### AshAuthentication
- **Add-ons:** log_out_everywhere; confirmation (monitor email, confirm_on_create, require_interaction)
- **Tokens:** enabled, store_all_tokens, require_token_presence_for_authentication
- **Strategies:**
  - password: identity email, sign_in_tokens_enabled (30s lifetime), resettable
  - magic_link: identity email, registration_enabled, require_interaction
  - api_key: relationship valid_api_keys, attribute api_key_hash

### Email Senders
- `SendMagicLinkEmail`
- `SendPasswordResetEmail`
- `SendNewUserConfirmationEmail`
- Uses Swoosh + Phoenix.VerifiedRoutes (unverified_url on JidoHubWeb.Endpoint)

### Secrets
- `JidoHub.Secrets` - fetches `:token_signing_secret` from Application env

## Constraints & Validations

- **Username:** normalization + uniqueness checks (Changes.NormalizeUsername, EnsureUniqueUsername)
- **Password:** min_length 8, confirmation validation, BcryptProvider hashing
- **Email:** ci_string format + identities, confirmation workflow via add-on
- **Policies:** bypass for AshAuthentication interactions, sign-in actions generate tokens
- **Tokens:** store_all_tokens true, presence required for authentication
