# Gap Analysis Summary: JidoHub vs Petal Pro

**Generated:** 2025-01-20

This document summarizes the analysis of JidoHub's current implementation compared to Petal Pro features for API/OpenAPI and Search/Filtering/Pagination.

## Executive Summary

JidoHub has solid infrastructure in place but lacks feature activation. The **Ash Framework provides superior alternatives** to Petal Pro's manual Ecto approach, making implementation simpler than a direct port.

### Quick Status

| Feature Area | Infrastructure | Implementation | Priority | Complexity |
|-------------|---------------|----------------|----------|-----------|
| **API & OpenAPI** | ✅ Ready | ❌ Not configured | HIGH | SIMPLE (1-2 days) |
| **Search & Filtering** | ⚠️ UI only | ❌ No DB queries | HIGH | MODERATE (3-5 days) |
| **Pagination** | ❌ Missing | ❌ Not implemented | HIGH | MODERATE (3-5 days) |

## 1. API & OpenAPI

### What JidoHub Has
- ✅ `ash_json_api` (~> 1.0) and `open_api_spex` (~> 3.0) installed
- ✅ Router, pipelines, and SwaggerUI endpoints configured
- ✅ API authentication via AshAuthentication.Strategy.ApiKey
- ✅ AshTypescript RPC endpoints functional

### What's Missing
- ❌ No resources exposed (AshJsonApiRouter has empty `domains: []`)
- ❌ No `json_api` blocks in any Ash resources
- ❌ No OpenAPI schema definitions
- ❌ SwaggerUI shows empty (no endpoints to document)

### Recommendation: **START HERE**
**Why:** Infrastructure is 90% complete. Adding `json_api` blocks to existing resources is straightforward and Ash handles most API logic automatically.

**Next Steps:**
1. Add `AshJsonApi.Resource` extension to User, Organization, Pod resources
2. Configure `json_api` blocks with type and routes
3. Register domains in AshJsonApiRouter: `domains: [JidoHub.Accounts, JidoHub.Organizations, JidoHub.Pods]`
4. Test CRUD operations via JSON:API
5. Verify SwaggerUI documentation

**Implementation Complexity: SIMPLE (1-2 days)**
- Ash's declarative approach generates API layer automatically
- No need for manual controllers like Petal Pro
- Authentication already working
- Testing infrastructure already exists

### Code Example
```elixir
# lib/jido_hub/accounts/user.ex
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
end

# lib/jido_hub_web/ash_json_api_router.ex
defmodule JidoHubWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [JidoHub.Accounts, JidoHub.Organizations, JidoHub.Pods],
    open_api: "/open_api"
end
```

## 2. Search, Filtering & Pagination

### What JidoHub Has
- ✅ Command palette with fuzzy search (in-memory, 150ms debounce)
- ✅ Workspace navigation search (in-memory, 300ms debounce)
- ✅ Dashboard and workflow search modals
- ✅ Search event handlers and state management

### What's Missing
- ❌ No database-backed search/filtering
- ❌ No pagination (no `stream()`, no page controls)
- ❌ No Flop or QueryBuilder dependencies
- ❌ No sortable table headers
- ❌ No URL parameter binding for shareable views
- ❌ No reusable pagination components

### Key Architectural Difference

**Petal Pro:** Uses Ecto + Flop + QueryBuilder + custom DataTable components

**JidoHub:** Uses Ash Framework (which has built-in pagination, sorting, filtering)

**Decision:** Use Ash-native features rather than adding Flop complexity.

### Recommendation: **Ash-Native Approach**

**Why Ash is Better:**
1. Ash already does what Flop does (pagination, sorting, filtering)
2. No architectural mismatch (Flop expects Ecto, not Ash)
3. Declarative configuration vs manual query building
4. Consistent with rest of JidoHub architecture

**Next Steps:**
1. Add `pagination` blocks to Ash read actions (offset + keyset)
2. Configure sortable fields in Ash actions
3. Add search arguments to read actions
4. Update LiveViews to handle URL params for pagination/filters
5. Build simple pagination UI components (prev/next/page numbers)
6. Add sortable table headers
7. Refactor in-memory search to database queries

**Implementation Complexity: MODERATE (3-5 days)**
- Existing search is UI-only, needs DB refactoring
- No reusable table components yet
- URL state management needs to be added
- But Ash makes queries simpler than Ecto+Flop approach

### Code Example
```elixir
# In Ash resource
defmodule JidoHub.Pods.Pod do
  use Ash.Resource, ...

  actions do
    read :read do
      primary? true
      
      pagination do
        offset? true
        countable true
        default_limit 20
      end
      
      argument :search, :string
      argument :status, :atom
      
      prepare build(sort: [inserted_at: :desc])
      
      filter expr(
        if not is_nil(^arg(:status)) do
          status == ^arg(:status)
        else
          true
        end and
        if not is_nil(^arg(:search)) do
          contains(name, ^arg(:search)) or
          contains(description, ^arg(:search))
        else
          true
        end
      )
    end
  end
end

# In LiveView
def handle_params(params, _url, socket) do
  page = Map.get(params, "page", "1") |> String.to_integer()
  search = Map.get(params, "search")
  status = Map.get(params, "status")
  
  result = JidoHub.Pods.Pod
    |> Ash.Query.for_read(:read, %{search: search, status: status})
    |> Ash.Query.page(page: page, limit: 20)
    |> Ash.read!()
  
  {:noreply, assign(socket, 
    pods: result.results, 
    page: result.page.current_page,
    total_pages: result.page.total_pages,
    total_count: result.page.count
  )}
end

def handle_event("change_page", %{"page" => page}, socket) do
  params = Map.merge(socket.assigns.params, %{"page" => page})
  {:noreply, push_patch(socket, to: ~p"/pods?#{params}")}
end
```

## Implementation Roadmap

### Phase 1: API Foundation (Week 1)
**Priority: HIGH | Complexity: SIMPLE**

1. Configure JSON:API for core resources
   - Add `json_api` blocks to User, Organization, Pod
   - Register domains in AshJsonApiRouter
   - Test CRUD operations

2. Verify OpenAPI documentation
   - Check SwaggerUI shows endpoints
   - Add descriptions and examples
   - Test API authentication flow

**Deliverable:** Working JSON:API for core resources with documentation

### Phase 2: Pagination & Sorting (Week 1-2)
**Priority: HIGH | Complexity: MODERATE**

1. Add pagination to Ash read actions
   - Configure pagination blocks (offset + keyset)
   - Set sensible defaults (20 per page)
   - Test with large datasets

2. Implement sortable columns
   - Configure sortable fields in actions
   - Update LiveView to handle sort params
   - Build sortable table header components

3. Build pagination UI
   - Page navigation controls (prev/next/numbers)
   - Per-page limit selector
   - Total count display

**Deliverable:** Paginated, sortable lists for Pods, Organizations, Users

### Phase 3: Search & Filtering (Week 2-3)
**Priority: MEDIUM | Complexity: MODERATE**

1. Refactor search to database queries
   - Add search arguments to Ash actions
   - Implement full-text search on relevant fields
   - Remove in-memory filtering where appropriate

2. Add filter UI
   - Status filters (dropdown/tags)
   - Type filters
   - Date range filters
   - Clear all filters button

3. URL state management
   - Bind filters to URL params
   - Shareable filtered views
   - Browser back/forward support

**Deliverable:** Database-backed search and filtering with URL state

### Phase 4: Advanced Features (Future)
**Priority: LOW**

1. Advanced API features
   - Custom controllers for complex workflows
   - Batch operations
   - Webhooks
   - Rate limiting

2. Advanced filtering
   - Port Petal Pro DataTable (if needed)
   - Column-level filter operators
   - Saved filter presets
   - Export functionality

## Key Decisions Made

### ✅ Use Ash-Native Pagination (Not Flop)
**Reason:** Ash already provides pagination, sorting, and filtering. Adding Flop creates architectural mismatch and complexity.

### ✅ Start with API Configuration (Not Search/Pagination)
**Reason:** Infrastructure is already in place. High value, low complexity. Quick win.

### ✅ Build Simple Pagination UI (Not Port DataTable)
**Reason:** Petal Pro DataTable is Flop-specific. Building Ash-native components is simpler and more maintainable.

### ✅ Database-Backed Search (Not Just Modal/In-Memory)
**Reason:** Current search is UI-only. Need proper queries for scalability and URL sharing.

## Resources

### Documentation
- [Ash Pagination Guide](https://hexdocs.pm/ash/pagination.html)
- [AshJsonApi Documentation](https://hexdocs.pm/ash_json_api)
- [Ash Filtering](https://hexdocs.pm/ash/read-actions.html#filtering)
- [Petal Pro DataTable Source](petal_pro/lib/petal_pro_web/components/pro_components/data_table/)

### Feature Docs
- [feature-api-and-openapi.md](../petal_features/feature-api-and-openapi.md)
- [feature-search-filtering-and-pagination.md](../petal_features/feature-search-filtering-and-pagination.md)

### Code References
- Router: [lib/jido_hub_web/router.ex](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/router.ex)
- AshJsonApiRouter: [lib/jido_hub_web/ash_json_api_router.ex](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/ash_json_api_router.ex)
- Domains: [lib/jido_hub/accounts.ex](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub/accounts.ex), [lib/jido_hub/organizations.ex](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub/organizations.ex), [lib/jido_hub/pods.ex](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub/pods.ex)
- Existing Search: [lib/jido_hub_web/components/ui/command_palette.ex](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/components/ui/command_palette.ex)

## Conclusion

JidoHub is well-positioned to implement both features. **The Ash Framework provides superior abstractions** compared to Petal Pro's manual Ecto approach:

- **API Layer:** Infrastructure ready, just needs configuration (1-2 days)
- **Search/Pagination:** Use Ash-native features rather than porting Flop (3-5 days)

**Total estimated effort:** 1-2 weeks for complete implementation of both features.

**Recommended order:** API first (quick win), then pagination, then advanced filtering.
