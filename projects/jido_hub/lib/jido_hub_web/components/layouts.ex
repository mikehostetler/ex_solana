defmodule JidoHubWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use JidoHubWeb, :html

  import JidoHubWeb.Components.SidebarNav

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    assigns = assign_new(assigns, :client_id, fn -> "#{assigns.id}-client" end)
    assigns = assign_new(assigns, :server_id, fn -> "#{assigns.id}-server" end)

    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id={@client_id}
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error ##{@client_id}") |> JS.remove_attribute("hidden")}
        phx-connected={hide("##{@client_id}") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id={@server_id}
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error ##{@server_id}") |> JS.remove_attribute("hidden")}
        phx-connected={hide("##{@server_id}") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Theme selector with optional icon-only mode.

  ## Attributes
  - `icon_only` - if true, renders icon-only button (default: false)
  - `position` - dropdown position: "end" or "top" (default: "end")
  """
  attr :icon_only, :boolean, default: false
  attr :position, :string, default: "end"

  def theme_toggle(assigns) do
    ~H"""
    <details class={["dropdown", "dropdown-#{@position}"]}>
      <summary
        class={if @icon_only, do: "icon-rail-btn", else: "btn btn-ghost btn-sm gap-2"}
        title={if @icon_only, do: "Change theme", else: nil}
        aria-label={if @icon_only, do: "Change theme", else: nil}
      >
        <.icon name="hero-swatch" class={if @icon_only, do: "w-5 h-5", else: "w-4 h-4"} />
        <span :if={!@icon_only} class="hidden sm:inline">Theme</span>
      </summary>
      <.theme_menu position={@position} />
    </details>
    """
  end

  defp theme_menu(assigns) do
    ~H"""
    <ul class={[
      "menu dropdown-content bg-base-200 rounded-box z-50 w-52 p-2 shadow",
      if(@position == "top", do: "mb-2", else: "mt-2")
    ]}>
      <li>
        <button type="button" data-set-theme="system" class="gap-2">
          <.icon name="hero-computer-desktop" class="w-4 h-4" /> System
        </button>
      </li>
      <li class="menu-title">
        <span>Light</span>
      </li>
      <li>
        <button type="button" data-set-theme="light" class="gap-2">
          <.icon name="hero-sun" class="w-4 h-4" /> Light
        </button>
      </li>
      <li>
        <button type="button" data-set-theme="cupcake" class="gap-2">
          <.icon name="hero-cake" class="w-4 h-4" /> Cupcake
        </button>
      </li>
      <li>
        <button type="button" data-set-theme="wireframe" class="gap-2">
          <.icon name="hero-pencil-square" class="w-4 h-4" /> Wireframe
        </button>
      </li>
      <li class="menu-title">
        <span>Dark</span>
      </li>
      <li>
        <button type="button" data-set-theme="dark" class="gap-2">
          <.icon name="hero-moon" class="w-4 h-4" /> Dark
        </button>
      </li>
      <li>
        <button type="button" data-set-theme="business" class="gap-2">
          <.icon name="hero-briefcase" class="w-4 h-4" /> Business
        </button>
      </li>
      <li>
        <button type="button" data-set-theme="nord" class="gap-2">
          <.icon name="hero-sparkles" class="w-4 h-4" /> Nord
        </button>
      </li>
    </ul>
    """
  end
end
