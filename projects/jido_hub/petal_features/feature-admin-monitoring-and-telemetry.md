# Feature: Admin, Monitoring & Telemetry

## Overview

The Admin, Monitoring & Telemetry feature provides comprehensive operational visibility into the JidoHub application through integrated dashboards and metrics instrumentation. It leverages Phoenix LiveDashboard for real-time system monitoring, Oban Web for background job management, and Telemetry for custom metrics collection. This feature enables administrators to monitor application health, diagnose performance issues, and observe system behavior in production environments.

The feature combines multiple observability tools into a unified admin interface, offering insights into database performance through Ecto PSQL Extras, background job status via Oban, and custom application metrics through Telemetry. It provides both real-time monitoring capabilities and historical metrics analysis, essential for maintaining system reliability and performance.

## Key Capabilities

- Phoenix LiveDashboard for real-time system metrics and process inspection
- Oban Web interface for background job monitoring and management
- Telemetry metrics collection and visualization for custom events
- Ecto PSQL Extras for PostgreSQL-specific performance insights
- DNS cluster coordination for distributed deployments
- Request telemetry for HTTP endpoint performance tracking
- Database query performance monitoring and analysis
- Live process inspection and debugging capabilities

## Architecture & Implementation

### Related Modules

- `lib/jido_hub_web/router.ex` - Dashboard route definitions and admin scope
- `lib/jido_hub_web/live/admin/` - Custom admin LiveView pages
- `lib/jido_hub/telemetry.ex` - Telemetry event handlers and metrics definitions
- `lib/jido_hub/application.ex` - Telemetry supervision and initialization
- `lib/jido_hub/repo.ex` - Database instrumentation configuration

### Key Dependencies

- `phoenix_live_dashboard` (~> 0.8.3) - Real-time monitoring interface
- `telemetry_metrics` (~> 1.0) - Metrics aggregation and reporting
- `telemetry_poller` (~> 1.0) - Periodic metrics collection
- `oban` (~> 2.0) - Background job processing
- `oban_web` (~> 2.0) - Oban monitoring interface
- `dns_cluster` (~> 0.2.0) - Distributed system coordination
- `ecto_sql` (~> 3.13) - Database instrumentation

## Integration Points

The monitoring and telemetry feature integrates with authentication systems to protect admin routes, typically requiring elevated privileges for access. It connects with the Oban job processing system to display queue status and job history, and instruments Ecto queries for database performance monitoring. Telemetry events are emitted throughout the application stack, from HTTP request handling in the router to business logic execution in Ash resources, providing end-to-end observability. The LiveDashboard mounts within the Phoenix router and shares the same authentication context as other admin interfaces.

## Adaptation Notes

When adapting this feature for JidoHub, ensure admin routes are properly secured with authentication checks consistent with JidoHub's user management system. Consider customizing the LiveDashboard home page with JidoHub-specific metrics and links. The Telemetry configuration may need custom event handlers for Ash-specific operations and Jido workflow execution. If deploying in a distributed environment, configure the DNS cluster settings appropriately for your infrastructure. Review the Oban Web configuration to ensure job queues align with JidoHub's background processing needs, and consider adding custom admin LiveView pages for JidoHub-specific administrative tasks like workflow monitoring or agent management.

## Gap Analysis: JidoHub vs Petal Pro

### Current JidoHub Implementation

**Monitoring & Dashboards:**
- [Phoenix LiveDashboard](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/router.ex#L179) configured at `/dev/dashboard` (dev only)
- [Oban Web](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/router.ex#L181) dashboard at `/dev/oban` (dev only)
- [Ash Admin](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/router.ex#L195) at `/dev/ash_admin` (dev only)
- Mailbox preview at `/dev/mailbox` (dev only)

**Telemetry Configuration:**
- [JidoHubWeb.Telemetry](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/telemetry.ex) module with comprehensive metrics:
  - Phoenix endpoint, router, socket, and channel metrics
  - Database query metrics (total_time, decode_time, query_time, queue_time, idle_time)
  - VM metrics (memory, run queue lengths)
  - Telemetry poller running every 10 seconds
- Basic metrics only, no custom application metrics yet
- No console reporter or external metrics export configured

**Admin Interface:**
- [Minimal admin dashboard](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/live/admin/dashboard_live.ex) at `/admin` with authentication
- Admin route protected by [RequireAdmin on_mount hook](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/router.ex#L120)
- Admin layout configured but minimal content
- No user management, logs viewer, or subscription management

**Security:**
- Dev routes disabled in production via config flag
- Authentication required for admin routes
- No role-based access control for different admin levels

### Missing from JidoHub

**Petal Pro Admin Features:**
1. **Admin LiveViews** (in `lib/petal_pro_web/live/admin/`):
   - admin_user_live/ - User management with search, edit, delete, membership management
   - admin_org_live/ - Organization management
   - admin_post_live/ - Content/post management
   - admin_subscriptions_live.ex - Subscription and billing management
   - admin_ai_chat_live/ - AI chat interface for admin tasks
   - dashboard/ - Full admin dashboard with stats and widgets
   - files/ - File management interface
   - logs/ - Application logs viewer with filtering

2. **Admin Layout Component:**
   - admin_layout_component.ex - Dedicated admin UI layout separate from app
   - Consistent admin navigation and styling
   - Admin-specific sidebars and menus

3. **Advanced Monitoring:**
   - Custom telemetry dashboards for business metrics
   - Application-specific metrics visualization
   - User activity tracking and analytics
   - Error tracking and alerting
   - Performance monitoring for critical paths

4. **Production Monitoring:**
   - Production-accessible admin interface (secured)
   - External metrics export (Prometheus, DataDog, etc.)
   - Alerting configuration
   - Health check endpoints
   - Uptime monitoring integration

5. **Operational Tools:**
   - Database query analyzer beyond basic Ecto metrics
   - Cache inspection and management
   - Feature flag management
   - Configuration viewer/editor
   - Background job retry and management tools
   - Email delivery tracking and debugging

### Implementation Priority

**HIGH Priority:**
1. **Admin user management LiveView** - Critical for managing users, roles, and permissions
2. **Logs viewer** - Essential for debugging production issues without SSH access
3. **Production-enabled monitoring** - LiveDashboard and Oban should be accessible in prod with proper auth
4. **Custom telemetry for Jido workflows** - Track workflow execution, agent performance, success/failure rates
5. **Admin layout component** - Consistent admin UI separate from main application

**MEDIUM Priority:**
1. **Admin dashboard with stats** - Overview of system health, active users, workflow metrics
2. **Organization management** - If multi-tenancy is core feature
3. **External metrics export** - DataDog, Prometheus, or CloudWatch integration
4. **Health check endpoints** - For load balancer and uptime monitoring
5. **Error tracking integration** - Sentry, Rollbar, or similar
6. **Background job management UI** - Beyond basic Oban Web (custom queues, priorities, scheduling)

**LOW Priority:**
1. **Admin AI chat** - Only if AI admin features are roadmap items
2. **File management interface** - Only needed if file uploads are implemented
3. **Content/post management** - Only if CMS features are needed
4. **Subscription management UI** - Only if implementing billing
5. **Advanced database query analyzer** - Nice-to-have beyond PSQL Extras
6. **Feature flag UI** - Only if feature flags are adopted

### Migration Complexity

**SIMPLE (2-4 hours each):**
- Health check endpoints - Basic HTTP endpoints returning system status
- Admin layout component - Port existing layout patterns to admin context
- Production route configuration - Update config to enable dashboards in prod with auth

**MODERATE (1-2 days each):**
- Logs viewer - Read and display application logs with filtering/search
- Admin dashboard with stats - Query and display key metrics
- User management LiveView - CRUD interface for users with search/filter
- Custom telemetry events - Add Jido-specific metrics to telemetry pipeline

**COMPLEX (3-5 days each):**
- Organization management - Full CRUD with permissions and member management
- External metrics export - Configure exporters, set up alerting, dashboard templates
- Error tracking integration - Integrate third-party service, configure error capture
- Advanced background job UI - Custom Oban management beyond default Web interface
- File management interface - Requires S3/storage integration, upload/download handling

**CRITICAL Path:**
1. **Enable prod monitoring** - Update router config to allow LiveDashboard/Oban in production with proper authentication
2. **Add Jido workflow telemetry** - Instrument workflow execution, agent actions, and errors
3. **Build admin user management** - Essential for managing platform users
4. **Create admin dashboard** - Central hub for admin operations with key metrics
5. **Implement logs viewer** - Production debugging capability

**Security Considerations:**
- All admin routes MUST be authenticated and authorization-checked
- Consider separate admin subdomain or VPN-only access for production
- Implement audit logging for admin actions
- Rate limiting on admin endpoints
- CSRF protection on all admin actions
- Consider 2FA requirement for admin access

**Recommended Immediate Actions:**
1. Move LiveDashboard, Oban Web to production with RequireAdmin authentication
2. Add custom telemetry for Jido workflow events (start, complete, error, duration)
3. Create admin dashboard landing page with system overview
4. Build logs viewer for production debugging
5. Plan user management interface based on role requirements
