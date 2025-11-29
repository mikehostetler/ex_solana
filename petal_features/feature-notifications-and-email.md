# Feature: Notifications and Email

## Overview
This feature provides a unified notification system that delivers messages through multiple channels: in-app notifications and transactional emails. Users receive consistent messaging across channels with proper formatting, tracking, and delivery guarantees. The system uses Oban for reliable background job processing, ensuring notifications are sent asynchronously without blocking request cycles.

Email delivery is handled by Swoosh with support for multiple SMTP adapters and email service providers. Templates use Phoenix components for consistency with the web UI, and Premailex automatically inlines CSS for broad email client compatibility. In-app notifications are stored in the database and rendered in real-time through LiveView, providing instant feedback for user actions.

## Key Capabilities
- Multi-channel delivery (email, in-app, extensible to SMS/push)
- Background job processing with retry logic via Oban
- Rich email templates with component reuse
- Automatic CSS inlining for email compatibility
- Email validation and deliverability checking
- Notification preferences and opt-out management
- Real-time in-app notification updates

## Architecture & Implementation

### Related Modules
- `lib/petal_pro/notifications/` - Notification records, delivery logic, user preferences
- `lib/petal_pro/emails/` - Email templates, mailer configuration, Swoosh setup
- `lib/petal_pro_web/components/notifications/` - UI components for in-app notifications

### Key Dependencies
- `swoosh` - Email composition and delivery
- `phoenix_swoosh` - Phoenix integration and mailbox preview
- `gen_smtp` - SMTP client for email sending
- `premailex` - Inline CSS for email compatibility
- `email_checker` - Email validation and deliverability checks
- `oban` - Background job processing and retry logic

## Integration Points
Notifications integrate deeply with user accounts for targeting and preferences, background job systems for reliable delivery, and the broader application for event triggers (new messages, completed workflows, system alerts). The in-app notification UI connects with LiveView navigation for clickable notifications that route users to relevant pages.

## Adaptation Notes
For JidoHub, extend notification types to cover AI agent events: workflow completions, errors, approval requests, and scheduled task reminders. Consider adding notification batching to avoid overwhelming users with high-frequency agent outputs. The preference system should allow granular control over which agent types and event severities trigger notifications. Email templates may need customization to display structured AI outputs (code blocks, data tables) in a readable format.

## Gap Analysis: JidoHub vs Petal Pro

### Current JidoHub Implementation
- **Basic email infrastructure**: 
  - [JidoHub.Mailer](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub/mailer.ex) configured with Swoosh
  - Local adapter for development (Swoosh.Adapters.Local)
  - Mailbox preview available at `/mailbox` route
  - Production SMTP adapter commented out in runtime.exs
  
- **Transactional emails**: Three basic email senders exist via AshAuthentication:
  - [SendNewUserConfirmationEmail](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub/accounts/user/senders/send_new_user_confirmation_email.ex) - Plain HTML confirmation link
  - [SendPasswordResetEmail](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub/accounts/user/senders/send_password_reset_email.ex) - Plain HTML reset link
  - [SendMagicLinkEmail](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub/accounts/user/senders/send_magic_link_email.ex) - Plain HTML login link
  
- **Notification preferences UI**: 
  - Toggle switches in [PreferencesLive](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/live/settings/preferences_live.ex#L14-L16) for email/push/workflow notifications
  - **Not persisted** - settings only stored in socket assigns, lost on page refresh
  - No backend storage or user preference schema
  
- **Infrastructure ready**:
  - Oban configured for background jobs (config/config.exs)
  - Phoenix.PubSub available for real-time events
  - Swoosh dependency installed (~> 1.16)

### Missing from JidoHub
1. **In-app notification system**
   - No notification schema/resource in database
   - No UI components for notification dropdown/sidebar
   - No real-time notification delivery via LiveView
   - No read/unread state tracking
   - No notification history or archive
   
2. **Advanced email features**
   - No rich HTML templates (current emails are basic HTML strings)
   - No Phoenix component-based email templates
   - No CSS inlining (missing `premailex` dependency)
   - No email validation (missing `email_checker` dependency)
   - No branded email layouts or styling
   - No email preview/testing tools beyond basic mailbox
   
3. **Notification delivery system** (`lib/*/notifications/`)
   - No abstraction for multi-channel delivery
   - No notification queue/Oban workers for async sending
   - No retry logic for failed deliveries
   - No delivery status tracking
   - No notification batching or digest emails
   
4. **User preferences**
   - Preferences not persisted to database
   - No granular notification type controls (only 3 broad toggles)
   - No opt-out management or unsubscribe tokens
   - No notification frequency settings (immediate vs digest)
   - No per-event-type or per-agent preferences
   
5. **Application event triggers**
   - No event system for "workflow completed", "agent failed", etc.
   - No notification templates for AI-specific events
   - No integration points for triggering notifications from business logic
   
6. **Email template system**
   - No reusable email components
   - No text/HTML multipart emails
   - No email localization support
   - No dynamic content rendering (only static templates)

### Implementation Priority
**HIGH** - Notifications are critical for:
- User engagement (workflow status updates, completion alerts)
- Error reporting (agent failures, system issues)
- Collaboration (team invitations, org updates - already referenced in preferences UI)
- Security (login alerts, suspicious activity)
- Retention (re-engagement emails, feature announcements)

JidoHub has notification UI already built but non-functional - users expect these toggles to work. Email templates are minimal and unprofessional for production use.

### Migration Complexity
**MODERATE to COMPLEX** - Implementation pathway:

1. **Quick wins (1-2 days)**: Fix existing functionality
   - Add User preference attributes (email_notifications, push_notifications, workflow_notifications)
   - Persist preference changes to database via Ash actions
   - Improve email templates with basic HTML/CSS styling
   - Add text fallback to existing emails
   
2. **Core notification system (1 week)**: 
   - Create Notification resource with Ash (id, user_id, type, title, body, read_at, metadata)
   - Build Oban worker for async notification delivery
   - Add in-app notification UI component (dropdown bell icon)
   - Implement PubSub broadcasting for real-time delivery
   - Create notification helpers for common events
   
3. **Email system enhancement (1 week)**:
   - Add `premailex` for CSS inlining
   - Build Phoenix component-based email templates
   - Create branded email layout with header/footer
   - Add text/HTML multipart support
   - Implement email validation with `email_checker`
   
4. **Advanced features (1-2 weeks)**:
   - Multi-channel notification router (in-app + email)
   - Notification batching and digest emails
   - Granular preference controls (per event type)
   - Delivery status tracking and retry logic
   - Unsubscribe token management
   - AI-specific notification templates (workflow results, agent outputs)

**Key complexity factors**:
- Ash framework integration for Notification resource and actions
- Real-time delivery requires LiveView integration and PubSub
- Email templating with Phoenix components needs careful design
- Preference management across multiple channels adds state complexity
- AI event integration requires defining event taxonomy
- Production email provider setup (SMTP credentials, deliverability)

**Recommendation**: Start with persisting notification preferences and upgrading email templates. Then build in-app notification system incrementally, starting with simple workflow completion alerts before adding advanced features like batching and multi-channel routing.
