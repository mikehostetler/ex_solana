defmodule JidoHubWeb.WorkspaceNav do
  @moduledoc """
  Sophisticated left navigation component using DaisyUI.
  Supports collapsible sections, modals for search/new, and dropdown menus.
  """
  use JidoHubWeb, :live_component

  import JidoHubWeb.Components.SidebarComponents
  import JidoHubWeb.CoreComponents

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <div class="flex-shrink-0 p-3">
        <div class="flex items-center justify-between gap-2">
          <.workspace_dropdown_header workspace_name={@workspace_name} current_user={@current_user} />
          <div class="flex items-center gap-1">
            <button
              class="btn btn-ghost btn-xs btn-square"
              title="Search (Cmd+K)"
              phx-click="open-search-modal"
              phx-target={@myself}
            >
              <.icon name="hero-magnifying-glass" class="w-4 h-4" />
            </button>
            <button
              class="btn btn-ghost btn-xs btn-square"
              title="New"
              phx-click="open-new-modal"
              phx-target={@myself}
            >
              <.icon name="hero-plus" class="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      <div class="flex-1 overflow-y-auto px-2 py-2">
        <nav class="menu menu-sm p-0 gap-0.5">
          <li>
            <a class="flex items-center gap-2 rounded-md !justify-between">
              <div class="flex items-center gap-2">
                <.icon name="hero-inbox" class="w-4 h-4" />
                <span>Inbox</span>
              </div>
              <span class="badge badge-sm badge-primary">3</span>
            </a>
          </li>
          <li>
            <a class="flex items-center gap-2 rounded-md">
              <.icon name="hero-clipboard-document-list" class="w-4 h-4" />
              <span>My Issues</span>
            </a>
          </li>
        </nav>

        <.nav_section title="Workspace">
          <li>
            <a class="flex items-center gap-2 rounded-md">
              <.icon name="hero-folder" class="w-4 h-4" />
              <span>Projects</span>
            </a>
          </li>
          <li>
            <a class="flex items-center gap-2 rounded-md">
              <.icon name="hero-view-columns" class="w-4 h-4" />
              <span>Views</span>
            </a>
          </li>
          <li>
            <.nav_more_dropdown>
              <li>
                <a class="flex items-center gap-2">
                  <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
                  <span>Settings</span>
                </a>
              </li>
              <li>
                <a class="flex items-center gap-2">
                  <.icon name="hero-archive-box" class="w-4 h-4" />
                  <span>Archive</span>
                </a>
              </li>
            </.nav_more_dropdown>
          </li>
        </.nav_section>

        <.collapsible_section
          id="teams-section"
          title="Your teams"
          expanded={@teams_expanded}
          target={@myself}
        >
          <.team_item
            id="jidohub-team"
            name="JidoHub"
            initials="Ji"
            expanded={@jidohub_team_expanded}
            target={@myself}
          >
            <li>
              <a class="flex items-center gap-2 rounded-md">
                <.icon name="hero-users" class="w-4 h-4" />
                <span>Teams</span>
              </a>
            </li>
            <li>
              <a class="flex items-center gap-2 rounded-md">
                <.icon name="hero-user-group" class="w-4 h-4" />
                <span>Members</span>
              </a>
            </li>
            <li>
              <a class="flex items-center gap-2 rounded-md">
                <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
                <span>Customize sidebar</span>
              </a>
            </li>
            <li>
              <a class="flex items-center gap-2 rounded-md">
                <.icon name="hero-view-columns" class="w-4 h-4" />
                <span>Views</span>
              </a>
            </li>
            <li>
              <.nav_more_dropdown>
                <li>
                  <a class="flex items-center gap-2">
                    <.icon name="hero-clipboard-document-list" class="w-4 h-4" />
                    <span>Team Issues</span>
                  </a>
                </li>
                <li>
                  <a class="flex items-center gap-2">
                    <.icon name="hero-chart-bar" class="w-4 h-4" />
                    <span>Analytics</span>
                  </a>
                </li>
                <li><hr class="my-1" /></li>
                <li>
                  <a class="flex items-center gap-2 text-error">
                    <.icon name="hero-trash" class="w-4 h-4" />
                    <span>Leave Team</span>
                  </a>
                </li>
              </.nav_more_dropdown>
            </li>
          </.team_item>
        </.collapsible_section>

        <.nav_section title="Try">
          <li>
            <a class="flex items-center gap-2 rounded-md">
              <.icon name="hero-arrow-down-tray" class="w-4 h-4" />
              <span>Import issues</span>
            </a>
          </li>
          <li>
            <a class="flex items-center gap-2 rounded-md">
              <.icon name="hero-plus" class="w-4 h-4" />
              <span>Invite people</span>
            </a>
          </li>
          <li>
            <a class="flex items-center gap-2 rounded-md">
              <.icon name="hero-rocket-launch" class="w-4 h-4" />
              <span>Initiatives</span>
            </a>
          </li>
          <li>
            <a class="flex items-center gap-2 rounded-md">
              <.icon name="hero-code-bracket" class="w-4 h-4" />
              <span>Link GitHub</span>
            </a>
          </li>
        </.nav_section>
      </div>

      <div class="flex-shrink-0 p-3">
        <div class="space-y-2">
          <.dismissible_card
            id="whats-new-card"
            type="info"
            icon="hero-sparkles"
            title="What's new"
            description="Label descriptions and archiving"
          />

          <.dismissible_card
            id="status-card"
            type="success"
            icon="hero-check-circle"
            title="All systems operational"
            description="Everything running smoothly"
          />
        </div>
      </div>

      <.search_modal
        show={@show_search_modal}
        myself={@myself}
        query={@search_query}
        results={@search_results}
      />
      <.new_item_modal show={@show_new_modal} myself={@myself} />
    </div>
    """
  end

  defp workspace_dropdown_header(assigns) do
    is_admin = assigns[:current_user] && assigns.current_user.role == :admin
    assigns = assign(assigns, :is_admin, is_admin)

    ~H"""
    <details class="dropdown">
      <summary class="btn btn-ghost btn-sm px-2 h-8 min-h-0">
        <span class="font-semibold text-sm">{@workspace_name}</span>
        <.icon name="hero-chevron-down" class="w-3 h-3 opacity-60" />
      </summary>
      <ul class="menu dropdown-content bg-base-200 rounded-box z-50 w-52 p-1.5 shadow mt-2">
        <li>
          <.link
            navigate="/settings/profile"
            class="flex items-center gap-2 text-sm px-3 py-2 rounded-md hover:bg-base-300"
          >
            <.icon name="hero-user-circle" class="w-4 h-4" />
            <span>Profile</span>
          </.link>
        </li>
        <li>
          <.link
            navigate="/settings"
            class="flex items-center gap-2 text-sm px-3 py-2 rounded-md hover:bg-base-300"
          >
            <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
            <span>Settings</span>
          </.link>
        </li>
        <li :if={@is_admin}>
          <.link
            navigate="/admin"
            class="flex items-center gap-2 text-sm px-3 py-2 rounded-md hover:bg-base-300"
          >
            <.icon name="hero-shield-check" class="w-4 h-4" />
            <span>Admin</span>
          </.link>
        </li>
        <li class="divider my-1"></li>
        <li>
          <.link
            navigate="/logout"
            class="flex items-center gap-2 text-sm px-3 py-2 rounded-md hover:bg-base-300"
          >
            <.icon name="hero-arrow-right-on-rectangle" class="w-4 h-4" />
            <span>Log out</span>
          </.link>
        </li>
      </ul>
    </details>
    """
  end

  defp collapsible_section(assigns) do
    ~H"""
    <div class="mt-4">
      <div class="px-2 py-1 text-xs font-medium opacity-50">{@title}</div>
      <div class="mt-1">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp team_item(assigns) do
    ~H"""
    <div>
      <button
        class="flex items-center gap-2 w-full px-2 py-1.5 rounded-md hover:bg-base-200 transition-colors"
        phx-click={"toggle-team-#{@id}"}
        phx-target={@target}
      >
        <div class="w-4 h-4 rounded bg-primary flex items-center justify-center text-primary-content text-[10px] font-bold">
          {@initials}
        </div>
        <span class="text-sm font-medium flex-1 text-left">{@name}</span>
        <.icon
          name="hero-chevron-down"
          class={"w-3 h-3 opacity-60 transition-transform #{@expanded && "rotate-180"}"}
        />
      </button>
      <div class={["ml-6 mt-1", !@expanded && "hidden"]}>
        <nav class="menu menu-sm p-0 gap-0.5">
          {render_slot(@inner_block)}
        </nav>
      </div>
    </div>
    """
  end

  defp search_modal(assigns) do
    ~H"""
    <dialog id="search-modal" class="modal" open={@show}>
      <div class="modal-box max-w-2xl">
        <form method="dialog">
          <button
            class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
            phx-click="close-search-modal"
            phx-target={@myself}
          >
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
        </form>
        <h3 class="text-section-header mb-4">Search</h3>
        <div class="form-control">
          <label class="input input-bordered flex items-center gap-2">
            <.icon name="hero-magnifying-glass" class="w-4 h-4 opacity-70" />
            <input
              type="text"
              placeholder="Search workflows, projects, issues..."
              class="grow"
              phx-keyup="search"
              phx-debounce="300"
              phx-target={@myself}
              value={@query}
              autofocus
            />
          </label>
        </div>

        <div class="mt-4">
          <%= if @query && @query != "" do %>
            <%= if Enum.empty?(@results) do %>
              <div class="text-center py-8 text-base-content/60">
                <.icon name="hero-magnifying-glass" class="w-12 h-12 mx-auto mb-2 opacity-30" />
                <p class="text-sm">No results found for "{@query}"</p>
              </div>
            <% else %>
              <div class="space-y-2">
                <%= for result <- @results do %>
                  <a class="flex items-center gap-3 p-3 rounded-lg hover:bg-base-200 transition-colors cursor-pointer">
                    <.icon name={result.icon} class="w-5 h-5 opacity-60" />
                    <div class="flex-1 min-w-0">
                      <div class="font-medium text-sm">{result.title}</div>
                      <div class="text-xs opacity-60 truncate">{result.description}</div>
                    </div>
                  </a>
                <% end %>
              </div>
            <% end %>
          <% else %>
            <div class="text-center py-8 text-base-content/60">
              <.icon name="hero-magnifying-glass" class="w-12 h-12 mx-auto mb-2 opacity-30" />
              <p class="text-sm">Start typing to search...</p>
            </div>
          <% end %>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop" phx-click="close-search-modal" phx-target={@myself}>
        <button>close</button>
      </form>
    </dialog>
    """
  end

  defp new_item_modal(assigns) do
    ~H"""
    <dialog id="new-item-modal" class="modal" open={@show}>
      <div class="modal-box">
        <form method="dialog">
          <button
            class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
            phx-click="close-new-modal"
            phx-target={@myself}
          >
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
        </form>
        <h3 class="text-section-header mb-4">Create New</h3>
        <div class="space-y-2">
          <button class="btn btn-ghost w-full justify-start gap-3">
            <.icon name="hero-document-plus" class="w-5 h-5" />
            <div class="text-left">
              <div class="font-medium">New Workflow</div>
              <div class="text-xs opacity-60">Create a new workflow</div>
            </div>
          </button>
          <button class="btn btn-ghost w-full justify-start gap-3">
            <.icon name="hero-folder-plus" class="w-5 h-5" />
            <div class="text-left">
              <div class="font-medium">New Project</div>
              <div class="text-xs opacity-60">Start a new project</div>
            </div>
          </button>
          <button class="btn btn-ghost w-full justify-start gap-3">
            <.icon name="hero-clipboard-document-list" class="w-5 h-5" />
            <div class="text-left">
              <div class="font-medium">New Issue</div>
              <div class="text-xs opacity-60">Report an issue or task</div>
            </div>
          </button>
          <button class="btn btn-ghost w-full justify-start gap-3">
            <.icon name="hero-view-columns" class="w-5 h-5" />
            <div class="text-left">
              <div class="font-medium">New View</div>
              <div class="text-xs opacity-60">Create a custom view</div>
            </div>
          </button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop" phx-click="close-new-modal" phx-target={@myself}>
        <button>close</button>
      </form>
    </dialog>
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       workspace_name: "JidoHub",
       teams_expanded: true,
       jidohub_team_expanded: false,
       show_search_modal: false,
       show_new_modal: false,
       search_query: "",
       search_results: []
     )}
  end

  @impl true
  def handle_event("open-search-modal", _params, socket) do
    {:noreply, assign(socket, show_search_modal: true)}
  end

  @impl true
  def handle_event("close-search-modal", _params, socket) do
    {:noreply, assign(socket, show_search_modal: false, search_query: "", search_results: [])}
  end

  @impl true
  def handle_event("open-new-modal", _params, socket) do
    {:noreply, assign(socket, show_new_modal: true)}
  end

  @impl true
  def handle_event("close-new-modal", _params, socket) do
    {:noreply, assign(socket, show_new_modal: false)}
  end

  @impl true
  def handle_event("toggle-team-jidohub-team", _params, socket) do
    {:noreply, assign(socket, jidohub_team_expanded: !socket.assigns.jidohub_team_expanded)}
  end

  @impl true
  def handle_event("search", %{"value" => query}, socket) do
    results = perform_search(query)
    {:noreply, assign(socket, search_query: query, search_results: results)}
  end

  defp perform_search(""), do: []

  defp perform_search(query) do
    [
      %{
        icon: "hero-document",
        title: "Workflow: #{query}",
        description: "Sample workflow matching your search"
      },
      %{
        icon: "hero-folder",
        title: "Project: #{query}",
        description: "Sample project matching your search"
      }
    ]
  end
end
