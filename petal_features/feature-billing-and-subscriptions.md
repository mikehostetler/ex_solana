# Feature: Billing and Subscriptions

## Overview
The Billing and Subscriptions feature provides a complete Stripe-backed monetization system for SaaS applications. This feature handles subscription lifecycle management, payment processing, plan changes, trial periods, and usage-based billing through tight integration with Stripe's APIs and webhook system.

The implementation uses background job processing to reliably handle Stripe webhooks, ensuring that subscription state changes, payment failures, and invoice events are processed asynchronously without blocking user requests. Payment methods are securely managed through Stripe's hosted interfaces, keeping sensitive card data out of the application database.

Organizations (not individual users) are the billable entities, allowing team-based pricing models where one subscription covers all members of an organization. The system tracks subscription status, current plans, trial periods, and payment history to control feature access and enforce plan limits.

## Key Capabilities
- Stripe subscription creation and management
- Multiple subscription plans with configurable pricing
- Trial period support with automatic conversion to paid
- Payment method management via Stripe Checkout and Billing Portal
- Webhook processing for real-time subscription updates
- Plan upgrades, downgrades, and cancellations
- Invoice generation and payment tracking
- Subscription status-based feature gating
- Grace periods for failed payments
- Proration handling for mid-cycle plan changes

## Architecture & Implementation

### Related Modules
- `lib/petal_pro/billing/` - Core billing domain
  - Subscription schema and lifecycle management
  - Plan definitions and pricing logic
  - Customer synchronization with Stripe
  - Payment method handling
- `lib/petal_pro_web/controllers/billing/` - HTTP endpoints
  - Stripe webhook receiver
  - Checkout session creation
  - Billing portal redirects
- `lib/petal_pro/workers/` - Background job processing
  - Webhook event processors
  - Subscription state sync jobs
  - Invoice finalization handlers
  - Payment retry logic

### Key Dependencies
- `stripity_stripe` - Official Stripe API client for Elixir
- `money` - Money data structure and currency calculations
- `currency_formatter` - Localized currency display formatting
- `oban` - Reliable background job processing for webhooks
- `jason` - JSON encoding/decoding for Stripe API payloads

## Integration Points
The Billing feature integrates with:
- **Organizations**: Subscriptions are owned by organizations, not individual users
- **Authentication**: Subscription status affects access to protected routes and features
- **Authorization**: Plan-based feature flags control capability access
- **Background Jobs (Oban)**: All webhook processing runs asynchronously to ensure reliability
- **Email System**: Sends payment receipts, trial expiration notices, and failure alerts
- **Admin Dashboard**: Provides subscription overview and management tools
- **Database**: Stores subscription state, plan information, and payment history

## Adaptation Notes
When extracting this into JidoHub:
- Replace `petal_pro` namespace with `jido_hub` equivalents
- Consider implementing billing as Ash resources with actions for lifecycle events
- Use `ash_oban` for webhook processing instead of raw Oban workers
- Leverage Ash calculations for computed subscription fields (days_until_trial_end, is_active, etc.)
- Implement Ash policies to enforce subscription-based access control
- Use Ash preparations/changes for Stripe API calls within resource actions
- Consider `ash_money` or custom Ash types for money/currency fields
- Map Stripe webhook events to Ash action inputs for idempotent processing
- Use `ash_paper_trail` to audit subscription changes and payment events
