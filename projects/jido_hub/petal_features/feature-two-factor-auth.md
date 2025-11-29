# Feature: Two-Factor Authentication

## Overview
This feature adds an additional layer of security through Time-based One-Time Password (TOTP) two-factor authentication. Users can enable 2FA on their accounts, which requires them to provide a time-sensitive code from an authenticator app in addition to their password when logging in. The enrollment process includes QR code generation for easy setup with popular authenticator apps like Google Authenticator or Authy.

The implementation follows TOTP standards (RFC 6238) to ensure compatibility with standard authenticator applications. Once enabled, 2FA becomes a required step in the authentication flow, significantly improving account security by requiring possession of a secondary device for access.

## Key Capabilities
- TOTP-based two-factor authentication
- QR code generation for easy authenticator app enrollment
- Backup codes for account recovery
- Enable/disable 2FA through security settings
- 2FA verification during login flow
- User management of 2FA status

## Architecture & Implementation

### Related Modules
- `lib/petal_pro/accounts/two_factor` - Core 2FA logic and TOTP generation/verification
- `lib/petal_pro_web/live/settings/security` - Security settings LiveView for 2FA enrollment and management

### Key Dependencies
- `nimble_totp` - TOTP generation and verification
- `eqrcode` - QR code generation for authenticator app setup

## Integration Points
Two-factor authentication integrates with the core authentication system by adding an additional verification step after successful password authentication. It extends the user account schema to store 2FA secrets and backup codes. The feature hooks into the login flow to require TOTP verification when enabled and provides UI components in the security settings area for users to manage their 2FA configuration.

## Adaptation Notes
When adapting to JidoHub, ensure the user schema can accommodate 2FA secret storage and backup codes. The 2FA flow requires modifications to the authentication pipeline to add the verification step after password auth. Consider whether backup code generation and management is needed for account recovery scenarios. The QR code generation UI should be reviewed to ensure it matches JidoHub's design patterns and security requirements.

## Gap Analysis: JidoHub vs Petal Pro

### Current JidoHub Implementation

JidoHub has **basic 2FA UI placeholders** but **no actual TOTP implementation**:

**Security Settings UI** ([lib/jido_hub_web/live/settings/security_live.ex](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/live/settings/security_live.ex))
- Two-factor authentication section exists in SecurityLive
- Enable/disable 2FA buttons present
- Status badge showing "Enabled" or "Disabled"
- Event handlers `enable_2fa` and `disable_2fa` present but only toggle local state
- No actual TOTP generation, verification, or storage
- State tracked in socket assign `two_factor_enabled: false` (in-memory only)

**User Schema** ([lib/jido_hub/accounts/user.ex](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub/accounts/user.ex))
- No 2FA-related fields (e.g., `totp_secret`, `backup_codes`, `two_factor_enabled_at`)
- No database columns for storing TOTP secrets
- No actions for 2FA enrollment or verification

**Authentication Flow**
- No 2FA verification step in login process
- No middleware to check 2FA status after password authentication
- Login goes directly from password validation to session creation

**Dependencies**
- `nimble_totp` - **NOT** present in mix.exs
- `eqrcode` - **NOT** present in mix.exs
- No QR code generation capability

### Missing from JidoHub

**Core 2FA Functionality**
- TOTP secret generation and storage
- QR code generation for authenticator app enrollment
- TOTP code verification during login
- Backup code generation, storage, and verification
- 2FA enforcement middleware/plug

**Database Schema**
- `totp_secret` field (encrypted) for storing user's TOTP secret
- `two_factor_enabled_at` timestamp field
- `backup_codes` field (encrypted array or separate resource)
- `backup_codes_generated_at` timestamp

**User Actions & Workflows**
- `:enable_two_factor` action - Generate secret, return QR code data
- `:verify_two_factor_enrollment` action - Verify initial TOTP code before enabling
- `:disable_two_factor` action - Require current TOTP code to disable
- `:verify_totp_code` action - Validate TOTP during login
- `:regenerate_backup_codes` action - Create new backup codes
- `:verify_backup_code` action - Use backup code for 2FA verification

**Authentication Pipeline Modifications**
- Post-password authentication hook to check 2FA status
- 2FA verification LiveView page (e.g., `/login/verify-2fa`)
- Session state to track "password_verified_but_needs_2fa" status
- Redirect logic from login to 2FA verification page
- Option to "trust this device" for 30 days

**Enrollment UI**
- QR code display component
- Manual secret entry option (for manual authenticator setup)
- Test TOTP code input before finalizing enrollment
- Backup codes display with download/print options
- Warning messages about securing backup codes

**Recovery Mechanisms**
- Backup code verification during login
- Support contact for account recovery
- Option to disable 2FA via email verification if locked out

**Security Features**
- Rate limiting on TOTP verification attempts
- Audit logging of 2FA events (enabled, disabled, verification attempts)
- Time-based window configuration (default 30 seconds)
- Option for admin to require 2FA for all users

### Implementation Priority

**High Priority**
- **Core TOTP Enrollment** - Essential foundation for 2FA feature
- **Login Verification Flow** - Required for 2FA to actually secure accounts
- **Backup Codes** - Critical for account recovery without TOTP device
- **Database Schema** - Must store secrets securely

**Medium Priority**
- **QR Code Generation** - Improves UX but manual entry is fallback
- **Enrollment Verification** - Prevents lockout from setup errors
- **Audit Logging** - Important for security monitoring
- **Rate Limiting** - Prevents brute force attacks

**Low Priority**
- **Trust This Device** - Nice UX feature but adds complexity
- **Admin-Enforced 2FA** - Only needed for enterprise/compliance scenarios
- **Email-Based Recovery** - Alternative to backup codes

### Migration Complexity

**Core TOTP Implementation: Moderate-Complex**
- Add `nimble_totp` and `eqrcode` dependencies to mix.exs
- Extend User resource with encrypted TOTP fields using `ash_cloak` (already available)
- Create Ash actions for enable/disable/verify workflows
- Implement TOTP verification logic with time window handling
- Integrate AshAuthentication hooks for post-password verification
- Database migration for new fields
- Petal Pro's `lib/petal_pro/accounts/two_factor` module can serve as reference
- **Estimated effort: 4-5 days**

**2FA Verification Flow: Moderate**
- Create new LiveView for TOTP code entry (`/login/verify`)
- Modify `AuthController` to redirect to verification page after password success
- Session state management for "partial authentication"
- LiveView form with 6-digit code input
- Handle "Use backup code" toggle
- **Estimated effort: 2-3 days**

**QR Code Enrollment UI: Simple-Moderate**
- Update SecurityLive with enrollment modal
- Generate QR code using `eqrcode`
- Display secret for manual entry
- Require test code verification before enabling
- Show backup codes with copy/download functionality
- **Estimated effort: 2 days**

**Backup Codes: Simple**
- Generate 8-10 single-use backup codes
- Store hashed versions in database (or encrypted array)
- Display codes once during generation
- Mark codes as used after verification
- Regeneration action
- **Estimated effort: 1-2 days**

**Database Schema Changes: Simple**
- Migration to add fields:
  - `totp_secret` (encrypted string)
  - `two_factor_enabled_at` (utc_datetime_usec)
  - `backup_codes` (encrypted JSONB array)
  - `backup_codes_generated_at` (utc_datetime_usec)
- Configure `ash_cloak` vault for encryption
- **Estimated effort: 0.5 day**

**Security Enhancements: Moderate**
- Rate limiting on TOTP endpoint (use existing rate limiter)
- Audit logging resource for 2FA events
- Admin enforcement policy (optional)
- **Estimated effort: 1-2 days**

**Total Estimated Effort: 11-15 days** (assumes AshAuthentication integration complexities)
