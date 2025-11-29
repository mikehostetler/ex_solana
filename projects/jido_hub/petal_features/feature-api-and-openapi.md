# Feature: API & OpenAPI

## Overview
This feature provides a comprehensive JSON API layer with automatically generated OpenAPI documentation. It enables external integrations and programmatic access to system resources through well-defined RESTful endpoints, complete with interactive documentation via Swagger UI.

The implementation leverages OpenAPI Spex for schema validation and documentation generation, ensuring that API contracts are both machine-readable and human-friendly. This approach provides type safety at the API boundary while maintaining flexibility for client consumption.

## Key Capabilities
- RESTful JSON API endpoints for resource access
- Automatic OpenAPI 3.0 specification generation
- Interactive Swagger UI documentation hosting
- Request/response schema validation
- Type-safe API contracts with compile-time checks
- Standardized error responses

## Architecture & Implementation

### Related Modules
- `lib/petal_pro_web/controllers/api/` - API controller implementations
- `lib/petal_pro_web/schemas/` - OpenAPI Spex schema definitions
- `lib/petal_pro_web/router.ex` - API route definitions and scope configuration

### Key Dependencies
- `open_api_spex` - OpenAPI specification generation and validation
- `jason` - JSON encoding/decoding
- `phoenix` - Web framework and controller foundation

## Integration Points
The API layer sits atop the core domain logic, consuming context functions from `lib/petal_pro/*` to expose business capabilities externally. It integrates with Phoenix's plug pipeline for authentication, authorization, and request processing. The OpenAPI schemas can be used to generate client libraries or drive contract testing.

## Adaptation Notes
When extracting into JidoHub, consider which resources need external API access. The schema definitions in `lib/petal_pro_web/schemas/` will need to be adapted to match JidoHub's domain models. Evaluate whether to expose agent and workflow resources via API, and consider API versioning strategy for future evolution. The OpenAPI documentation can serve as the foundation for public API documentation.

## Gap Analysis: JidoHub vs Petal Pro

### Current JidoHub Implementation

**Infrastructure Present:**
- ✅ `ash_json_api` dependency installed (~> 1.0)
- ✅ `open_api_spex` dependency installed (~> 3.0)
- ✅ `JidoHubWeb.AshJsonApiRouter` module created
- ✅ OpenAPI/SwaggerUI endpoints configured at `/api/v1/swaggerui` and legacy `/api/json/swaggerui`
- ✅ API pipeline with authentication (ApiKey strategy) at `:api` and `:api_flex`
- ✅ JSON:API parser configured in endpoint
- ✅ AshTypescript RPC endpoints at `/api/v1/rpc/run` and `/api/v1/rpc/validate`

**Current Limitations:**
- ❌ No resources exposed via JSON:API (AshJsonApiRouter has empty `domains: []`)
- ❌ No Ash resources configured with `AshJsonApi.Resource` extension
- ❌ No `json_api` blocks in User, Organization, Pod, or other resources
- ❌ No OpenApiSpex schema definitions for domain models
- ❌ No custom API controllers for complex operations
- ❌ SwaggerUI configured but shows empty API (no endpoints to document)

### Missing from JidoHub

**Petal Pro Has:**

1. **RESTful API Controllers** (`lib/petal_pro_api/controllers/`)
   - SessionController - authentication endpoints
   - RegistrationController - user signup
   - ProfileController - user profile CRUD
   - Custom JSON views for each controller

2. **OpenAPI Schema Definitions** (`lib/petal_pro_api/schemas.ex`)
   - UserCredentials schema
   - AuthResponse schema
   - UserRegistration schema
   - User profile schemas
   - UpdateProfile schema
   - Error response schemas

3. **Comprehensive API Spec** (`lib/petal_pro_api/api_spec.ex`)
   - Bearer token security scheme
   - Standardized error responses (401, 403, 422, 204)
   - Server configuration from endpoint
   - Automatic schema discovery
   - Reusable response components

4. **API-Specific Router Configuration**
   - Dedicated API scope with versioning
   - OpenAPI spec endpoint at `/api/open_api`
   - Request/response validation middleware
   - Clear separation of API and web concerns

**What JidoHub Needs:**

1. **Resource-Level JSON:API Configuration**
   - Add `json_api` blocks to Ash resources (User, Organization, Pod, etc.)
   - Configure which actions to expose (index, show, create, update, destroy)
   - Define serialization rules and field visibility
   - Set up relationship inclusion rules

2. **Domain-Level JSON:API Registration**
   - Register domains in AshJsonApiRouter: `domains: [JidoHub.Accounts, JidoHub.Organizations, JidoHub.Pods]`
   - Configure JSON:API routes per domain

3. **OpenAPI Schema Definitions**
   - Create schema modules for JidoHub domain models
   - Define request/response schemas for Pods, Workflows, Executions
   - Document authentication and authorization schemes
   - Add validation rules and examples

4. **Custom API Endpoints** (if needed beyond JSON:API)
   - Workflow execution endpoints
   - Agent task submission
   - Batch operations
   - Complex queries not suitable for JSON:API

### Implementation Priority

**HIGH - Core API Foundation**
- Configure existing Ash resources with `AshJsonApi.Resource` extension
- Add `json_api` blocks to User, Organization, Pod resources
- Register domains in AshJsonApiRouter
- Test that basic CRUD operations work via JSON:API

**MEDIUM - Documentation & Schemas**
- Create OpenAPI schema definitions for core domain models
- Document authentication flow (API key + bearer token)
- Add examples and descriptions to API endpoints
- Ensure SwaggerUI shows complete, usable documentation

**LOW - Advanced Features**
- Custom API controllers for complex workflows
- API versioning strategy beyond /api/v1
- Rate limiting and throttling
- API client SDK generation from OpenAPI spec
- Webhook endpoints for async notifications

### Migration Complexity

**SIMPLE** (1-2 days)
- Adding `json_api` blocks to existing Ash resources is straightforward
- Ash handles most serialization, relationship loading, and pagination automatically
- Basic OpenAPI integration via AshJsonApi is largely automatic
- Testing can leverage existing factories and test helpers

**Why It's Simple:**
1. Infrastructure already in place (ash_json_api, open_api_spex, router, pipelines)
2. Ash's declarative approach means most API behavior is configured, not coded
3. JSON:API spec handles standardization of request/response formats
4. Authentication already working via ApiKey strategy

**Example Configuration Needed:**

```elixir
# In lib/jido_hub/accounts/user.ex
defmodule JidoHub.Accounts.User do
  use Ash.Resource,
    domain: JidoHub.Accounts,
    extensions: [AshAuthentication, AshJsonApi.Resource]

  json_api do
    type "user"
    
    routes do
      base "/users"
      get :read
      index :read
      patch :update
      delete :destroy
    end
  end
  
  # ... rest of resource
end

# In lib/jido_hub_web/ash_json_api_router.ex
defmodule JidoHubWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [JidoHub.Accounts, JidoHub.Organizations, JidoHub.Pods],
    open_api: "/open_api"
end
```

**MODERATE Complexity** for:
- Comprehensive OpenAPI schema documentation (requires detailed schema definitions)
- Custom controllers for non-CRUD operations (requires Phoenix controller expertise)
- Advanced authorization rules (requires understanding of Ash policies and JSON:API filtering)

**Recommendation:**
Start with HIGH priority items. The Ash+AshJsonApi approach is actually simpler than Petal Pro's manual controller approach, as Ash generates the API layer automatically from resource definitions. Focus on configuring resources correctly rather than building controllers from scratch.
