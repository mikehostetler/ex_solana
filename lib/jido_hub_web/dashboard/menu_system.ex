defmodule JidoHubWeb.Dashboard.MenuSystem do
  @moduledoc """
  Global menu system that drives navigation, commands, and keyboard shortcuts
  throughout the dashboard.

  Provides a centralized menu hierarchy with support for:
  - Navigation routes
  - Command palette actions
  - Keyboard shortcuts
  - Permission/feature gating
  - Nested menu structures
  - Visual separators and badges
  """

  defmodule MenuItem do
    @moduledoc """
    Represents a single menu item with navigation, action, and metadata.
    """

    @type t :: %__MODULE__{
            id: atom(),
            label: String.t(),
            icon: String.t() | nil,
            to: String.t() | nil,
            action: atom() | nil,
            keyboard: String.t() | nil,
            section: atom() | nil,
            subsection: atom() | nil,
            items: [t()],
            separator: boolean(),
            badge: String.t() | nil,
            requires: atom() | [atom()] | nil
          }

    defstruct [
      :id,
      :label,
      :icon,
      :to,
      :action,
      :keyboard,
      :section,
      :subsection,
      :badge,
      :requires,
      items: [],
      separator: false
    ]
  end

  @doc """
  Returns the complete menu hierarchy for the dashboard.

  The menu tree is organized into sections:
  - Main: Dashboard and workflows
  - Workspace: Agents and pods with subsections
  - Teams: Team switcher
  - Settings: Configuration

  Each item can have navigation routes, actions, keyboard shortcuts,
  and nested items for submenus.
  """
  @spec menu_tree() :: [MenuItem.t()]
  def menu_tree do
    [
      # Main Section
      %MenuItem{
        id: :dashboard,
        label: "Dashboard",
        icon: "hero-home",
        to: "/",
        keyboard: "g d",
        section: :main
      },
      %MenuItem{
        id: :workflows,
        label: "Workflows",
        icon: "hero-arrow-path",
        to: "/workflows",
        keyboard: "g w",
        section: :main
      },
      %MenuItem{
        id: :separator_main,
        label: "",
        separator: true
      },
      # Workspace Section - Agents
      %MenuItem{
        id: :agents,
        label: "Agents",
        icon: "hero-cpu-chip",
        section: :workspace,
        items: [
          %MenuItem{
            id: :agents_all,
            label: "All Agents",
            to: "/agents",
            keyboard: "g a",
            subsection: :agents
          },
          %MenuItem{
            id: :agents_active,
            label: "Active",
            to: "/agents/active",
            subsection: :agents
          },
          %MenuItem{
            id: :agents_idle,
            label: "Idle",
            to: "/agents/idle",
            subsection: :agents
          },
          %MenuItem{
            id: :agents_stopped,
            label: "Stopped",
            to: "/agents/stopped",
            subsection: :agents
          }
        ]
      },
      # Workspace Section - Pods
      %MenuItem{
        id: :pods,
        label: "Pods",
        icon: "hero-cube",
        section: :workspace,
        items: [
          %MenuItem{
            id: :pods_all,
            label: "All Pods",
            to: "/pods",
            keyboard: "g p",
            subsection: :pods
          },
          %MenuItem{
            id: :pods_running,
            label: "Running",
            to: "/pods/running",
            subsection: :pods
          },
          %MenuItem{
            id: :pods_paused,
            label: "Paused",
            to: "/pods/paused",
            subsection: :pods
          },
          %MenuItem{
            id: :pods_failed,
            label: "Failed",
            to: "/pods/failed",
            badge: "3",
            subsection: :pods
          }
        ]
      },
      %MenuItem{
        id: :separator_workspace,
        label: "",
        separator: true
      },
      # Teams Section
      %MenuItem{
        id: :teams,
        label: "Teams",
        icon: "hero-users",
        action: :show_team_switcher,
        keyboard: "t",
        section: :teams
      },
      %MenuItem{
        id: :separator_teams,
        label: "",
        separator: true
      },
      # Settings Section
      %MenuItem{
        id: :settings,
        label: "Settings",
        icon: "hero-cog-6-tooth",
        to: "/settings",
        keyboard: "g s",
        section: :settings
      }
    ]
  end

  @doc """
  Returns a flat list of all actionable menu items.

  Filters out structural items (separators, items without `to` or `action`).
  """
  @spec commands() :: [MenuItem.t()]
  def commands do
    menu_tree()
    |> flatten_menu_items([])
    |> Enum.reject(fn item ->
      is_nil(item.to) and is_nil(item.action)
    end)
  end

  @doc """
  Returns a map of keyboard shortcuts to their menu items.

  Keys are keyboard sequences (e.g., "g d"), values are MenuItem structs.
  """
  @spec keyboard_shortcuts() :: %{String.t() => MenuItem.t()}
  def keyboard_shortcuts do
    commands()
    |> Enum.filter(fn item -> not is_nil(item.keyboard) end)
    |> Map.new(fn item -> {item.keyboard, item} end)
  end

  @doc """
  Finds a menu item by its ID.

  Returns the MenuItem struct or nil if not found.
  """
  @spec find_item(atom()) :: MenuItem.t() | nil
  def find_item(id) do
    menu_tree()
    |> flatten_menu_items([])
    |> Enum.find(fn item -> item.id == id end)
  end

  defp flatten_menu_items([], acc), do: Enum.reverse(acc)

  defp flatten_menu_items([item | rest], acc) do
    nested = flatten_menu_items(item.items, [])
    flatten_menu_items(rest, Enum.reverse(nested, [item | acc]))
  end
end
