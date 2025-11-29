# Feature: Background Jobs and Scheduling

## Overview

This feature provides robust asynchronous job processing and scheduling capabilities built on Oban. It handles critical background tasks including email delivery, webhook processing, data cleanup operations, and billing synchronization. The system supports advanced job management patterns like retries, deduplication, and cron-based scheduling, making it suitable for production workloads that require reliability and observability.

Oban Web integration provides real-time visibility into job queues, execution history, and system health. This observability layer is essential for monitoring background operations and debugging failures in production environments.

## Key Capabilities

- Asynchronous job processing with configurable queues and priorities
- Automatic retry logic with exponential backoff for failed jobs
- Job deduplication to prevent redundant work
- Cron-based scheduling for recurring tasks
- Real-time job monitoring and observability via Oban Web
- Telemetry integration for metrics and monitoring
- Admin interface for job management and inspection

## Architecture & Implementation

### Related Modules

- `lib/petal_pro/workers/` - Worker modules that process jobs
- `lib/petal_pro/jobs/` - Job definitions and enqueue functions
- `lib/petal_pro_web/live/admin/oban/` - Admin LiveViews for job monitoring

### Key Dependencies

- `oban` - Core job processing engine
- `oban_web` - Web dashboard for observability
- `telemetry_metrics` - Metrics collection and reporting

## Integration Points

Jobs are enqueued from various parts of the application: user actions trigger webhook deliveries, scheduled tasks handle cleanup operations, and transactional events spawn email jobs. The Oban engine integrates with Ecto for persistence and uses PostgreSQL-based queuing for reliability. The admin interface connects through Phoenix LiveView for real-time updates.

## Adaptation Notes

When extracting to JidoHub, consider which specific job types are needed and configure appropriate queues. The Oban setup can be simplified by removing unused workers. Ensure database migrations for Oban tables are included. The admin interface requires authentication guards to restrict access to authorized users only.

## Gap Analysis: JidoHub vs Petal Pro

### Current JidoHub Implementation

**Core Infrastructure:**
- ✅ Oban configured in `application.ex` using `AshOban.config`
- ✅ Basic queue configuration: `queues: [default: 10]`
- ✅ Oban.Plugins.Cron plugin registered (but empty config)
- ✅ Oban ~> 2.0 and oban_web ~> 2.0 in mix.exs dependencies

**AshOban Integration:**
- Using declarative job system via `ash_oban` extension
- Email senders use `AshAuthentication.Sender` behavior (not traditional Oban workers)
- Jobs handled through Ash resource actions, not explicit worker modules

**Existing Background Jobs:**
1. `SendNewUserConfirmationEmail` - Email delivery via AshAuthentication
2. `SendMagicLinkEmail` - Magic link authentication emails
3. `SendPasswordResetEmail` - Password reset emails

**Configuration:**
```elixir
config :jido_hub, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10],
  repo: JidoHub.Repo,
  plugins: [{Oban.Plugins.Cron, []}]
```

### Missing from JidoHub

**Critical Missing Components:**

1. **Oban Web Dashboard** - No admin interface mounted for job monitoring
2. **Cron Jobs** - Plugin registered but no scheduled tasks configured
3. **Custom Worker Modules** - No traditional Oban.Worker implementations
4. **Queue Management** - Only single "default" queue, no priority or specialized queues
5. **Job Enqueueing Interface** - No explicit job scheduling API outside AshAuthentication

**Missing Worker Types:**
- Webhook delivery workers
- Data cleanup/maintenance workers
- Report generation workers
- Billing/subscription sync workers
- Notification aggregation workers
- Cache warming/invalidation workers

**Missing Observability:**
- No Oban Web routes configured
- No admin interface for viewing job history
- No job failure alerting
- No queue monitoring dashboard
- Limited telemetry integration

**Missing Advanced Features:**
- Job deduplication strategies
- Priority queue configuration
- Custom retry strategies
- Job lifecycle callbacks
- Dead letter queue handling
- Job batching for bulk operations

### Implementation Priority

**HIGH Priority:**
1. Mount Oban Web dashboard for production observability
2. Configure multiple queues (email, webhooks, maintenance, default)
3. Add authentication guards for Oban Web access
4. Implement basic cron jobs (cleanup, health checks)

**MEDIUM Priority:**
5. Create webhook delivery worker pattern
6. Add telemetry integration for job metrics
7. Configure retry strategies and backoff
8. Implement job deduplication for critical operations

**LOW Priority:**
9. Advanced scheduling patterns (complex cron expressions)
10. Job batching and bulk processing
11. Custom queue priorities and throttling
12. Dead letter queue and failure alerting

### Migration Complexity

**SIMPLE to MODERATE Complexity**

**Easy Components:**
- ✅ Oban fully configured and running
- ✅ Database tables already migrated
- ✅ Dependencies installed (oban, oban_web)
- ✅ Basic AshOban integration working for emails
- ✅ No worker migration needed (using AshOban declarative approach)

**Moderate Components:**
- 🟡 Mounting Oban Web requires router configuration + auth guards
- 🟡 Cron jobs need schedule definitions and health check implementations
- 🟡 Queue configuration requires analysis of job types and priorities
- 🟡 Telemetry integration needs metrics collection setup

**Architectural Considerations:**
- **AshOban vs Traditional Workers**: JidoHub uses declarative job system through Ash resources rather than explicit worker modules. This is **valid and modern** but differs from Petal Pro's traditional approach
- **Hybrid Approach Possible**: Can mix AshOban triggers with traditional workers for specialized tasks
- **No Breaking Changes Needed**: Current implementation works, additions are incremental

**Estimated Effort:** 1-2 days for essentials, 3-5 days for full-featured implementation

**Quick Wins:**
1. Mount Oban Web (30 minutes) - Instant production visibility
2. Add cron health check job (1 hour) - Verify system health
3. Configure email queue separately (30 minutes) - Better email delivery control
4. Add auth guard to Oban Web (1 hour) - Secure admin interface

**Risk Factors:**
- **LOW RISK**: Infrastructure already solid, only additions needed
- Authentication guard must be properly configured for Oban Web
- Cron schedules should use timezone-aware configuration
- Queue sizing may need tuning under production load
