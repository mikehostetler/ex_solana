# Feature: Authentication and User Management

## Overview
This feature provides comprehensive user authentication and account management capabilities for the application. It supports multiple authentication methods including traditional email/password authentication secured with bcrypt, as well as OAuth-based social sign-in through Google and GitHub. The system handles the complete user lifecycle from initial registration through email confirmation, login, password reset, and ongoing session management.

The authentication system is built on proven security practices and leverages industry-standard protocols for OAuth integration. It provides a flexible foundation that can accommodate various authentication workflows while maintaining security best practices for credential storage and session handling.

## Key Capabilities
- Email/password authentication with bcrypt password hashing
- OAuth social sign-in via Google and GitHub
- User registration with email confirmation
- Password reset and recovery workflows
- Session management and user authentication state
- Account management and profile updates

## Architecture & Implementation

### Related Modules
- `lib/petal_pro/accounts` - Core account and user domain logic
- `lib/petal_pro_web/controllers/auth` - Authentication controllers for OAuth callbacks
- `lib/petal_pro_web/live/auth` - LiveView components for auth UI (login, registration, reset)

### Key Dependencies
- `bcrypt_elixir` - Password hashing and verification
- `ueberauth` - Pluggable authentication framework
- `ueberauth_google` - Google OAuth strategy
- `ueberauth_github` - GitHub OAuth strategy

## Integration Points
The authentication system integrates deeply with the user management system and provides authentication context to all protected routes. It works with the session management layer to maintain user state across requests and coordinates with email delivery systems for confirmation and password reset workflows. OAuth integrations connect to external identity providers while maintaining a unified user identity within the application.

## Adaptation Notes
When extracting to JidoHub, consider which OAuth providers are required and whether the existing account schema meets your needs. The authentication flows are tightly coupled with Phoenix controller and LiveView patterns, so adaptation will require careful review of the auth pipeline plugs and LiveView mount hooks. Email confirmation and password reset workflows depend on email delivery infrastructure that must be configured separately.

## Gap Analysis: JidoHub vs Petal Pro

### Current JidoHub Implementation

JidoHub has implemented a comprehensive authentication system using **AshAuthentication** instead of Petal Pro's custom implementation:

**User Schema & Domain** ([lib/jido_hub/accounts/user.ex](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub/accounts/user.ex))
- Ash Resource-based user model with built-in authentication extensions
- Email/password authentication with bcrypt hashing via `AshAuthentication.BcryptProvider`
- Username field with GitHub-style normalization and validation
- Role-based access control (`:user`, `:admin`)
- Email confirmation workflow with `confirmed_at` field
- Token-based authentication with dedicated token resource

**Authentication Strategies**
1. **Password Strategy** - Email/password with sign-in tokens (30 second lifetime)
2. **Magic Link Strategy** - Passwordless email-based authentication with registration support
3. **API Key Strategy** - Token-based API authentication with relationship to valid API keys

**Authentication Flows** ([lib/jido_hub_web/controllers/auth_controller.ex](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/controllers/auth_controller.ex))
- Custom `AuthController` using `AshAuthentication.Phoenix.Controller`
- Login via `/auth/user/password/sign_in` (password)
- Registration via `/auth/user/password/register`
- Magic link via `:request_magic_link` action
- Sign out via `/logout` route
- Password reset via token-based workflow
- Email confirmation via `confirm_route` helper

**LiveView Authentication Pages**
- [LoginLive](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/live/login_live.ex) - `/login` with magic link toggle
- [RegisterLive](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/live/register_live.ex) - `/signup` with username validation
- [PasswordResetRequestLive](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/live/password_reset_request_live.ex) - `/reset`

**Session Management** ([lib/jido_hub_web/live_user_auth.ex](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/live_user_auth.ex))
- `LiveUserAuth` on_mount hooks for authentication state
- `:live_user_optional` - Load user if present
- `:live_user_required` - Enforce authentication
- `:live_no_user` - Redirect authenticated users
- Session-based storage via `store_in_session/2`
- Bearer token support for API authentication
- API key authentication via plugs

**Email Senders** ([lib/jido_hub/accounts/user/senders/](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub/accounts/user/senders/))
- `SendNewUserConfirmationEmail` - Email verification
- `SendPasswordResetEmail` - Password reset workflow
- `SendMagicLinkEmail` - Passwordless sign-in
- All senders implement `AshAuthentication.Sender` behavior

**Dependencies**
- `ash_authentication` - Core authentication framework
- `ash_authentication_phoenix` - Phoenix integration
- `bcrypt_elixir` - Password hashing
- Token resource with JWT support

### Missing from JidoHub

**OAuth/Social Sign-In**
- No Ueberauth integration
- No Google OAuth provider (`ueberauth_google`)
- No GitHub OAuth provider (`ueberauth_github`)
- UI placeholders exist but marked "Coming Soon" (disabled buttons in login/register)
- No OAuth callback controller (`AuthController` for callbacks)
- No social account linking/unlinking

**Account Management Features**
- No dedicated accounts context module (Petal Pro has `lib/petal_pro/accounts`)
- No profile update workflows beyond basic settings
- No account deletion workflow (UI exists but not implemented)
- Limited user preference management

**Session Management**
- No multi-device session tracking
- No active session list/management UI (placeholder exists in SecurityLive)
- No "sign out all devices" functionality
- No session expiration policies beyond JWT defaults

**Security Enhancements**
- No password strength meter during registration
- No "remember me" functionality
- No suspicious login detection
- No account lockout after failed attempts
- No login history/audit log

### Implementation Priority

**High Priority**
- **OAuth Integration** - UI is already designed with placeholders; users expect social sign-in
- **Session Management** - SecurityLive has placeholder UI that needs backend implementation
- **Account Deletion** - Required for GDPR compliance; UI button exists but not wired

**Medium Priority**
- **Multi-Device Sessions** - Enhances security and user control
- **Password Strength Validation** - Improves account security
- **Login History/Audit** - Valuable for enterprise users and compliance

**Low Priority**
- **Remember Me** - Nice-to-have UX feature
- **Account Lockout** - Can leverage rate limiting initially
- **Social Account Linking** - Only needed after OAuth is implemented

### Migration Complexity

**OAuth Integration: Complex**
- Requires Ueberauth dependencies and configuration
- Need OAuth provider credentials (Google, GitHub)
- Must handle OAuth callback flows and error cases
- Social account linking strategy needed
- Database schema changes for provider identities
- Petal Pro's OAuth controller patterns can be adapted, but AshAuthentication has its own OAuth add-on approach
- Estimated effort: 3-5 days

**Session Management: Moderate**
- Database table for session tracking
- LiveView updates to SecurityLive (UI exists)
- Session listing and revocation actions
- Integration with existing auth tokens
- Petal Pro patterns transferable with Ash Resource adaptations
- Estimated effort: 2-3 days

**Account Deletion: Simple**
- Create Ash action for account deletion
- Add confirmation modal to SecurityLive
- Handle cascade deletion of related data
- Add "deleted_at" soft delete field
- Estimated effort: 1 day

**Password Strength & Validation: Simple**
- Client-side JS for strength meter
- Server-side validation rules (already have min 8 chars)
- Add to registration and password change forms
- Petal Pro likely has reusable client-side component
- Estimated effort: 1 day

**Login History/Audit Log: Moderate**
- New Ash resource for login attempts
- Background job for cleanup (Oban already available)
- UI for viewing history
- Estimated effort: 2-3 days
