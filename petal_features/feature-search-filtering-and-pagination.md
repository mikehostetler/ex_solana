# Feature: Search, Filtering & Pagination

## Overview
This feature provides a unified approach to querying, filtering, sorting, and paginating data across the application. It establishes consistent patterns for building complex queries while maintaining type safety and composability, making it straightforward to add search and filtering capabilities to any resource.

The implementation centers around reusable query builders that work seamlessly with LiveView components, providing a cohesive user experience for browsing large datasets. Pagination helpers automatically manage page state and generate navigation controls, reducing boilerplate in LiveView modules.

## Key Capabilities
- Composable query building with type-safe filters
- Multi-field search with customizable matching
- Flexible sorting with multiple column support
- Cursor and offset-based pagination strategies
- LiveView-integrated pagination components
- Consistent filtering patterns across resources
- URL parameter binding for shareable filtered views

## Architecture & Implementation

### Related Modules
- `lib/petal_pro/*` - Context modules with query helper functions
- `lib/petal_pro_web/components/pagination/` - Reusable pagination components
- Query builder utilities embedded in context modules

### Key Dependencies
- `flop` - Filtering, ordering, and pagination framework
- `query_builder` - Composable Ecto query construction
- `typed_ecto_schema` - Type-safe schema definitions
- `ecto` - Database query layer

## Integration Points
This feature integrates deeply with Ecto schemas and context functions, providing the query layer between LiveViews and the database. It works in tandem with LiveView's param handling to maintain filter and pagination state in URLs. The pagination components consume assigns set by Flop, creating a tight integration between backend filtering logic and frontend presentation.

## Adaptation Notes
When extracting into JidoHub, identify which resources need filtering and pagination (agents, workflows, executions, logs). The query patterns from `lib/petal_pro/*` contexts can be adapted to JidoHub's domain models. Consider which fields should be filterable and sortable for each resource. The pagination components should work largely unchanged, though styling may need adjustment. For agent and workflow listings, consider adding specialized filters for status, type, tags, or capabilities.

## Gap Analysis: JidoHub vs Petal Pro

### Current JidoHub Implementation

**Search & Filtering Present:**
- ✅ Command palette with fuzzy search (`lib/jido_hub_web/components/ui/command_palette.ex`)
  - Filter function with 150ms debounce
  - Keyboard navigation (arrow keys, Enter)
  - Grouped command results by category
  - Uses `String.downcase` and `String.contains?` for matching
- ✅ Workspace navigation search (`lib/jido_hub_web/components/workspace_nav.ex`)
  - Live search with 300ms debounce
  - `perform_search/1` function for filtering results
  - Search modal with real-time updates
- ✅ Dashboard search integration (`lib/jido_hub_web/live/dashboard_live.ex`)
  - Search query state management
  - `handle_event("search_filter")` for updates
  - Modal control events (open/close)
- ✅ Workflow listing search (`lib/jido_hub_web/live/workflow_live/index.ex`)
  - Similar search/filter patterns to dashboard
  - Command palette integration

**Current Limitations:**
- ❌ No Flop dependency or framework integration
- ❌ No QueryBuilder pattern for composable queries
- ❌ No pagination implementation (no `stream()`, no `Repo.paginate()`)
- ❌ No URL parameter binding for shareable filtered views
- ❌ No sortable table headers
- ❌ No filterable column components
- ❌ No cursor or offset-based pagination
- ❌ Search is modal/in-memory only, not query-based
- ❌ No database-level filtering or full-text search
- ❌ No reusable pagination components

### Missing from JidoHub

**Petal Pro Has:**

1. **Flop Framework Integration** (`mix.exs`)
   - `{:flop, "~> 0.20"}` - Filtering, ordering, and pagination
   - `{:query_builder, "~> 1.0"}` - Composable Ecto queries
   - `{:typed_ecto_schema, "~> 0.4.1"}` - Type-safe schemas

2. **DataTable Component** (`lib/petal_pro_web/components/pro_components/data_table/`)
   - `data_table.ex` - Main component with Flop integration
   - `data_table_header.ex` - Sortable column headers
   - `data_table_filter.ex` - Filter schema and UI
   - `data_table_filter_set.ex` - Multi-filter management
   - `data_table_cell.ex` - Cell rendering with types
   - Supports operators: `==`, `!=`, `=~`, `empty`, `not_empty`, `<=`, `<`, `>=`, `>`
   - Column-level filterable and sortable configuration
   - Type-aware rendering (integer, select, date, currency)

3. **Query Builder Pattern** (`lib/petal_pro/schema.ex`)
   - Base schema uses QueryBuilder automatically
   - Composable query functions in dedicated query modules
   - Example: `lib/petal_pro/accounts/user_query.ex`
     - `active?/1`, `deleted?/2`, `suspended?/2`
     - `text_search/2` with multi-field ILIKE
     - `order_by/2`, `limit/2`
     - Chainable query transformations

4. **LiveView Integration Pattern**
   ```elixir
   def handle_params(params, _url, socket) do
     starting_query = MyApp.Resource
     flop_opts = [default_limit: 10, default_order: %{...}]
     
     case Flop.validate_and_run(starting_query, params, flop_opts) do
       {:ok, {items, meta}} -> assign(socket, items: items, meta: meta)
       _ -> push_navigate(socket, to: ~p"/fallback")
     end
   end
   
   def handle_event("update_filters", %{"filters" => filter_params}, socket) do
     query_params = build_filter_params(socket.assigns.meta, filter_params)
     {:noreply, push_patch(socket, to: ~p"/path?#{query_params}")}
   end
   ```

5. **Pagination Components**
   - Reusable pagination UI consuming Flop meta
   - Page navigation controls
   - Per-page limit selector
   - Total count display
   - URL state persistence

**What JidoHub Needs:**

1. **Flop Integration**
   - Add `{:flop, "~> 0.20"}` dependency
   - Add `{:query_builder, "~> 1.0"}` dependency
   - Configure Flop in schemas that need pagination

2. **Ash-Compatible Pagination Strategy**
   - Ash has built-in pagination (keyset and offset)
   - Decision: Use Ash's pagination or add Flop on top?
   - If using Flop: Convert Ash queries to Ecto queries for Flop
   - If using Ash: Build DataTable-like components for Ash pagination

3. **Query Builder Modules**
   - Create query modules per domain (e.g., `PodQuery`, `WorkflowQuery`)
   - Add composable filter functions
   - Implement text search across relevant fields
   - Add status, type, tag filtering

4. **Reusable Table Components**
   - Either port Petal Pro DataTable or build Ash-native equivalent
   - Sortable column headers
   - Filterable columns with operators
   - Pagination controls
   - URL state binding

5. **LiveView Refactoring**
   - Update `handle_params` to process filter/sort/page params
   - Add `handle_event` for filter updates
   - Use `push_patch` for URL state management
   - Stream or assign paginated results

### Implementation Priority

**HIGH - Pagination Foundation**
- **Ash-native pagination** for Pod, Organization, User listings
- Configure `pagination` blocks in Ash read actions
- Add keyset pagination to main list views
- URL parameter handling in `handle_params`
- Test pagination with large datasets

Rationale: JidoHub uses Ash, not raw Ecto. Leverage Ash's built-in pagination rather than adding Flop complexity.

**MEDIUM - Sorting & Basic Filtering**
- Add sortable columns to LiveView tables
- Configure `sort` in Ash read actions
- Build filter forms for common fields (status, type, date ranges)
- Use Ash filters rather than raw query builders
- URL state for sort and filter params

**LOW - Advanced DataTable Port**
- Port Petal Pro DataTable component (if Ash pagination insufficient)
- Add Flop dependency for complex filter operators
- Build Ash-to-Ecto query adapter layer
- Implement column-level filter UI
- Add export/bulk actions

### Migration Complexity

**MODERATE** (3-5 days for basic implementation)

**Why Moderate:**
1. **Ash vs Ecto Mismatch**: Petal Pro uses Ecto+Flop, JidoHub uses Ash
   - Ash has its own query and pagination system
   - Flop expects Ecto queries, not Ash queries
   - Need to decide: Ash-native or Flop integration?

2. **Existing Search is UI-Only**: Current search filters in-memory data
   - Need to refactor to database-backed queries
   - Requires changes to LiveView logic and Ash actions
   - URL state management needs to be added

3. **No Reusable Components Yet**: JidoHub has custom search modals
   - Need to build or port DataTable-style components
   - Requires component architecture decisions
   - Styling integration with DaisyUI theme

**Recommended Approach - Ash-Native (Simpler):**

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
      
      prepare build(sort: [inserted_at: :desc])
      
      filter expr(
        if is_nil(^arg(:search)) do
          true
        else
          contains(name, ^arg(:search)) or
          contains(description, ^arg(:search))
        end
      )
    end
  end
end

# In LiveView
def handle_params(params, _url, socket) do
  page = Map.get(params, "page", 1)
  search = Map.get(params, "search")
  
  pods = JidoHub.Pods.Pod
    |> Ash.Query.for_read(:read, %{search: search})
    |> Ash.Query.page(page: page, limit: 20)
    |> Ash.read!()
  
  {:noreply, assign(socket, pods: pods.results, page_meta: pods.page)}
end
```

**COMPLEX if Porting DataTable:**
- Requires bridging Ash and Flop (not straightforward)
- Need to extract Ecto queries from Ash or teach Flop about Ash
- Significant component porting work
- May conflict with Ash patterns

**Recommendation:**
1. **Start with Ash-native pagination** - Use Ash's built-in pagination, sorting, and filtering
2. **Build simple pagination UI** - Page numbers, prev/next, per-page selector
3. **Add sortable table headers** - Use Ash's sort syntax
4. **Implement search as Ash filter arguments** - Pass search terms to Ash queries
5. **Skip Flop unless absolutely needed** - Ash already does what Flop does

The gap is moderate because of architectural mismatch, but using Ash's native features makes it simpler than porting Petal Pro's Ecto-centric approach.
