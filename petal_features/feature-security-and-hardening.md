# Feature: Security and Hardening

## Overview
This feature provides comprehensive application security through authentication, authorization, session management, and cryptographic protections. It establishes baseline security controls including CSRF protection, Content Security Policy (CSP) headers, secure secret management, and defense-in-depth mechanisms that protect both the application layer and data layer.

The security infrastructure implements industry best practices for password hashing, employs ID obfuscation to prevent enumeration attacks, uses modern UUIDv7 for primary keys, and includes automated security auditing tools. These components work together to create a hardened application that resists common web vulnerabilities while maintaining developer productivity.

## Key Capabilities
- Authentication and session management with secure token handling
- CSRF protection and Content Security Policy (CSP) enforcement
- Strong password hashing with bcrypt
- ID obfuscation using Hashids to prevent enumeration attacks
- UUIDv7 primary keys for improved database performance and security
- Automated security auditing with Sobelow
- Secret management and secure configuration patterns
- Security headers and HTTP hardening

## Architecture & Implementation

### Related Modules
- `lib/petal_pro_web/endpoint.ex` - CSP, session, and security header configuration
- `lib/petal_pro_web/router.ex` - Authentication pipelines and route protection
- `lib/petal_pro/accounts/` - User authentication and authorization logic
- `lib/petal_pro/auth/` - Token generation, password hashing, session management

### Key Dependencies
- `content_security_policy` - CSP header management and nonce generation
- `bcrypt_elixir` - Password hashing with configurable work factor
- `hashids` - Reversible ID obfuscation for public-facing identifiers
- `uuid_v7` - Time-ordered UUIDs for primary keys
- `sobelow` - Static security analysis for Phoenix applications

## Integration Points
The security layer integrates with Phoenix authentication through plugs and LiveView lifecycle hooks. Session management connects to the endpoint configuration, while authentication state flows through router pipelines to controllers and LiveViews. Security headers are applied globally through endpoint configuration but can be customized per-route. The ID obfuscation system integrates with Ecto schemas through custom types or helper functions, ensuring that all public-facing IDs are properly encoded.

## Adaptation Notes
When extracting to JidoHub, review the authentication strategy to ensure alignment with your user model and authorization requirements. The CSP configuration should be audited against your asset pipeline and any third-party integrations. Consider whether the Hashids implementation meets your obfuscation needs or if a different approach is warranted. Ensure that security auditing tools (Sobelow, mix audit) are integrated into your CI/CD pipeline. Review secret management patterns to align with your deployment infrastructure (environment variables, secret stores, etc.).

## Gap Analysis: JidoHub vs Petal Pro

### Current JidoHub Implementation
- **Authentication**: AshAuthentication with password, magic link, and API key strategies implemented
- **CSRF Protection**: Standard Phoenix `protect_from_forgery` plug in browser pipeline
- **Secure Headers**: Basic `put_secure_browser_headers` plug configured in router
- **Password Hashing**: bcrypt_elixir (v3.0) included in dependencies
- **Session Management**: Cookie-based sessions with signing_salt and same_site: "Lax"
- **UUIDv7**: Database functions for UUIDv7 support present in migrations
- **Encryption**: ash_cloak and cloak libraries included for field-level encryption
- **API Security**: API key authentication via AshAuthentication.Strategy.ApiKey

### Missing from JidoHub
- **Content Security Policy (CSP)**: No CSP headers or nonce generation configured
- **ID Obfuscation**: No Hashids or similar library for public-facing ID obfuscation
- **Sobelow**: Not included in mix.exs dependencies or quality aliases
- **Security Auditing**: No `mix audit` or automated security scanning in precommit/quality checks
- **Advanced Security Headers**: No X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy
- **Rate Limiting**: No rate limiting plugs or middleware
- **Secret Rotation**: No patterns for secret management beyond standard config
- **Security Testing**: No dedicated security test suite or penetration testing helpers

### Implementation Priority
**High Priority**:
- CSP configuration - Critical for XSS protection, especially with LiveView
- Sobelow integration - Low-effort, high-value security auditing
- ID obfuscation - Prevent enumeration attacks on public endpoints

**Medium Priority**:
- Enhanced security headers - Straightforward to add via endpoint configuration
- Rate limiting - Important for API and authentication endpoints
- Security testing suite - Should align with existing test infrastructure

**Low Priority**:
- Advanced secret rotation - Can use infrastructure-level solutions initially
- Dedicated security monitoring - Can leverage existing telemetry/observability

### Migration Complexity
**Simple** (1-2 hours):
- Adding Sobelow to mix.exs and quality checks
- Basic CSP headers via endpoint configuration
- Additional security headers (X-Frame-Options, etc.)

**Moderate** (4-8 hours):
- Full CSP with nonces for inline scripts/styles
- ID obfuscation with Hashids - requires Ecto type and helper implementation
- Rate limiting plugs with configurable thresholds

**Complex** (1-2 days):
- Comprehensive security testing suite
- Advanced CSP with asset pipeline integration
- Secret management patterns for multi-environment deployment
