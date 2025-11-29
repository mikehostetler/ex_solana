defmodule JidoHubWeb.IconPanel do
  @moduledoc """
  Far-left icon panel with vertical navigation icons.
  Always visible, fixed 56px width with dark background.
  """
  use Phoenix.Component
  use JidoHubWeb, :verified_routes

  import JidoHubWeb.CoreComponents

  attr :active, :atom, default: nil
  attr :class, :string, default: ""

  def render(assigns) do
    ~H"""
    <aside
      role="navigation"
      aria-label="Primary"
      class={[
        "flex flex-col items-center w-14 h-screen sticky top-0",
        "bg-base-300 text-base-content/70 py-3",
        "border-r border-base-300",
        @class
      ]}
      style="grid-area: icons"
    >
      <%!-- Top: Logo --%>
      <.link navigate={~p"/"} aria-label="Home" class="mb-2">
        <div class="w-10 h-10 rounded-md bg-base-100/50 border border-base-content/10 flex items-center justify-center text-xs font-semibold text-base-content">
          JI
        </div>
      </.link>

      <%!-- Middle: Primary nav --%>
      <div class="mt-2 flex-1 flex flex-col gap-1.5">
        <.nav_button
          to={~p"/workflows"}
          label="Workflows"
          icon="squares-2x2"
          active?={@active == :workflows}
        />
        <.nav_button to="#" label="Launch" icon="rocket-launch" active?={@active == :launch} />
      </div>

      <%!-- Bottom: Utilities --%>
      <div class="mt-auto flex flex-col gap-1.5">
        <.nav_button to="#" label="Docs" icon="clipboard-document-list" active?={@active == :docs} />
        <.nav_button to="#" label="Settings" icon="cog-6-tooth" active?={@active == :settings} />
        <.nav_button to="#" label="Profile" icon="user-circle" active?={@active == :me} />
      </div>
    </aside>
    """
  end

  attr :to, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :active?, :boolean, default: false

  defp nav_button(assigns) do
    ~H"""
    <.link patch={@to} aria-label={@label} class="group relative focus:outline-none">
      <div
        data-active={@active?}
        class="
          w-10 h-10 rounded-md flex items-center justify-center
          transition-colors duration-150
          text-base-content/60 hover:text-base-content
          hover:bg-base-200
          data-[active=true]:bg-base-100 data-[active=true]:text-base-content
          focus-visible:ring-2 focus-visible:ring-primary/40
        "
      >
        <.icon name={"hero-#{@icon}"} class="w-5 h-5" />
      </div>
      <%!-- Tooltip --%>
      <span class="
        pointer-events-none absolute left-full ml-2 top-1/2 -translate-y-1/2
        whitespace-nowrap rounded-md bg-base-content/90 text-base-100 text-xs
        px-2 py-1 opacity-0 shadow-lg ring-1 ring-base-content/20
        transition-opacity duration-100 group-hover:opacity-100
      ">
        {@label}
      </span>
    </.link>
    """
  end
end
