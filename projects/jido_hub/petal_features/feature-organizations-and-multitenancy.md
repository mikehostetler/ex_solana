# Feature: Organizations and Multitenancy

## Overview
The Organizations and Multitenancy feature provides a complete multi-tenant architecture enabling users to create and manage organizations with role-based access control. This system allows applications to serve multiple organizations (teams, companies, workspaces) within a single deployment, with proper data isolation and permission boundaries.

The feature implements a flexible membership model where users can belong to multiple organizations with different roles, while all data is scoped by `org_id` to ensure strict tenant isolation. Organization owners can invite members, assign roles, and manage team settings, creating a collaborative environment with appropriate access controls.

Built on a foundation of typed schemas and modern identifier systems, this feature provides the scaffolding for SaaS applications requiring team collaboration, workspace isolation, and hierarchical permission management.

## Key Capabilities
- Organization creation and management with customizable settings
- User invitations with email-based onboarding flow
- Role-based access control (owner, admin, member, custom roles)
- Multi-organization membership for users
- Tenant-scoped data queries with automatic `org_id` filtering
- Organization switching and context management
- Member management (invite, remove, update roles)
- Organization-level settings and preferences

## Architecture & Implementation

### Related Modules
- `lib/petal_pro/orgs/` - Core organization domain logic
  - Organization schema and context
  - Membership management
  - Invitation system
  - Role definitions and authorization
- `lib/petal_pro_web/live/orgs/` - LiveView interfaces
  - Organization dashboard
  - Member management screens
  - Invitation flows
  - Settings pages

### Key Dependencies
- `typed_ecto_schema` - Type-safe schema definitions for organizations and memberships
- `uuid_v7` - Time-ordered unique identifiers for organizations and invitations
- `hashids` - Human-friendly, obfuscated IDs for public-facing URLs
- `ecto_sql` / `postgrex` - Database layer for tenant data isolation

## Integration Points
The Organizations feature integrates deeply with:
- **Authentication**: Links users to organizations through membership records
- **Authorization**: Provides role-based permissions checked throughout the application
- **Database Queries**: Requires `org_id` scoping on all tenant-specific queries
- **LiveView Sessions**: Maintains current organization context in socket assigns
- **Billing**: Organizations serve as the subscription/payment entity (see Billing feature)
- **Background Jobs**: Jobs are scoped by organization for multi-tenant processing

## Adaptation Notes
When extracting this into JidoHub:
- Replace `petal_pro` namespace with `jido_hub` equivalents
- Consider using Ash Framework's built-in multitenancy support instead of manual `org_id` scoping
- Evaluate Ash's authorization policies for role-based access rather than custom authorization logic
- Integration with `ash_authentication` for user-organization relationships
- Leverage `ash_postgres` tenant strategies (foreign key vs schema-based isolation)
- Consider `ash_paper_trail` for auditing organization changes
- Map organization roles to Ash policy conditions and checks

## Gap Analysis: JidoHub vs Petal Pro

### Current JidoHub Implementation

**Core Resources (Fully Implemented)**
- [JidoHub.Organizations.Organization](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub/organizations/organization.ex) - Complete Ash resource with:
  - UUID primary keys, slug generation, owner relationship
  - CRUD actions: create (with auto-owner assignment), update, destroy, transfer_ownership
  - Ash policies for access control (owner + membership-based authorization)
  - Settings map for extensibility
  
- [JidoHub.Organizations.Membership](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub/organizations/membership.ex) - Complete join resource:
  - Three role types: :owner, :admin, :member
  - create, create_via_invite, update_role, destroy actions
  - Sophisticated policies including custom checks (CanManageMemberships, ActorIsAdminOrOwner)
  - Unique constraint on user_id + organization_id
  
- [JidoHub.Organizations.Invitation](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub/organizations/invitation.ex) - Full invitation system:
  - Token-based invitations with expiration
  - Email validation, duplicate prevention
  - Custom changes: GenerateToken, SetExpiration, AcceptInvitation, ValidateInvitationPermissions
  - Token-based lookup action with bypassed authorization for public acceptance
  
**Database Schema (Complete)**
- [Migration 20251008185342_initial.exs](file:///Users/mhostetler/Source/Jido/hub/jido_hub/priv/repo/migrations/20251008185342_initial.exs) includes:
  - organizations table with owner_id, slug, settings
  - memberships table with role, joined_at
  - invitations table with token, expires_at, accepted_at
  - Proper foreign key constraints and unique indexes

**Authorization Infrastructure**
- Custom Ash policy checks implemented:
  - [CanManageMemberships](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub/organizations/membership/checks/can_manage_memberships.ex)
  - [ActorIsAdminOrOwner](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub/organizations/membership/checks/actor_is_admin_or_owner.ex)
- Policies use Ash expressions and relationships for authorization

**Related Systems**
- [Pods system](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub/pods/pod.ex) supports organization ownership (polymorphic: user or org)
- [IsOrgAdmin check](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub/pods/pod/checks/is_org_admin.ex) for pod authorization

### Missing from JidoHub

**1. LiveView UI Components**
- No organization management LiveViews (dashboard, settings)
- No member management interface (list, invite, remove, change roles)
- No invitation acceptance flow UI
- Org switcher exists in [header component](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/components/dashboard/header.ex) but uses [sample data](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/dashboard/orgs.ex#L29-L47) not real organizations

**2. Organization Context Persistence**
- `switch_org` handler exists in [DashboardLive](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/live/dashboard_live.ex#L105-L109) but only updates socket assigns
- No session/cookie persistence of current_org selection
- No automatic org context loading in LiveView mount
- No org context in router pipeline

**3. Multi-Tenancy Data Scoping**
- No automatic `organization_id` filtering on queries
- Pods support org ownership but no automatic scoping by current org context
- No Ash multitenancy configuration (attribute-based or schema-based)
- Resources don't declare multitenancy strategy

**4. Email Notifications**
- No invitation email sending (invitation resource exists but no sender)
- No membership change notifications
- No organization activity emails
- Email infrastructure (Swoosh) installed but no org-specific templates

**5. Background Jobs Integration**
- Oban installed but no org-scoped jobs
- No cleanup jobs for expired invitations
- No org data export/archive jobs

**6. Advanced Features**
- No organization avatar/logo upload
- No organization billing entity integration (billing feature not implemented)
- No organization-level feature flags or plan limits
- No organization activity audit log (ash_paper_trail installed but not configured)
- No organization deletion with data cleanup
- No organization transfer workflow UI

**7. Dependencies**
- Missing `typed_ecto_schema` (Petal uses, JidoHub uses native Ash attributes)
- Missing `uuid_v7` (JidoHub uses default UUID4 via gen_random_uuid())
- Missing `hashids` (Petal uses for public-facing IDs)

### Implementation Priority

**High Priority**
1. **Organization Context Middleware** - Essential for proper multitenancy
   - Add LiveView mount callback to load user's orgs and current org
   - Persist current_org in session/assigns
   - Create Plug to inject org context into Ash queries

2. **Multi-Tenancy Scoping** - Critical for data isolation
   - Configure Ash multitenancy on relevant resources
   - Add organization_id to resources that need scoping (workflows, etc.)
   - Update policies to enforce tenant boundaries

3. **Member Management LiveView** - Core functionality
   - List organization members with roles
   - Invite new members (reuse existing Invitation resource)
   - Remove members, change roles
   - Link to existing invitation acceptance actions

**Medium Priority**
4. **Invitation Email Flow** - Complete the invitation system
   - Create Swoosh template for invitations
   - Add sender to Invitation.create action
   - Implement invitation acceptance landing page

5. **Organization Settings UI** - User-facing management
   - Organization profile (name, description, avatar)
   - Member list and management
   - Danger zone (transfer, delete)

6. **Real Org Switcher** - Replace sample data
   - Load user's organizations from database
   - Handle org switching with context persistence
   - Update header component to show real data

**Low Priority**
7. **Background Jobs** - Nice-to-have automation
   - Expired invitation cleanup job
   - Organization usage reports

8. **Advanced Features** - Future enhancements
   - Organization avatar uploads (requires file upload feature)
   - Billing integration (requires billing feature)
   - Audit logging with ash_paper_trail
   - Activity feeds

### Migration Complexity

**Simple (1-2 days)**
- Organization context persistence: Add assigns/session handling
- Real org switcher: Query user orgs and update component
- Invitation emails: Create template and wire to resource

**Moderate (3-5 days)**
- Member management UI: Build LiveView with forms, use existing resources
- Organization settings page: CRUD interface for Organization resource
- Multi-tenancy scoping setup: Configure Ash multitenancy, update policies

**Complex (1-2 weeks)**
- Full data isolation audit: Review all resources for tenant leaks
- Organization deletion with cascade: Data cleanup across all related resources
- Billing integration: Tie subscriptions to organizations (blocked on billing feature)

### Technical Notes

**Strengths of Current Implementation**
- Excellent Ash resource design with proper policies
- Invitation system is production-ready with validation and security
- Custom checks pattern is clean and reusable
- Database schema is well-normalized

**Architectural Considerations**
- JidoHub uses Ash Framework natively vs Petal's Ecto-centric approach
- Ash policies are more powerful than Petal's custom authorization
- Ash multitenancy features can replace manual org_id scoping
- No need for `typed_ecto_schema` - Ash provides type safety
- UUID strategy difference (gen_random_uuid vs uuid_v7) is minor
- Missing `hashids` not critical - can use slugs for public URLs

**Recommended Next Steps**
1. Start with org context middleware (enables everything else)
2. Configure Ash multitenancy on key resources
3. Build member management UI to activate existing backend
4. Add invitation emails to complete the loop
5. Gradually add organization settings and advanced features
