defmodule JidoHubWeb.Menus.MenuItem do
  @moduledoc """
  Represents a single menu item across all layouts.
  """

  @enforce_keys [:id, :label, :to]
  defstruct [:id, :label, :to, :icon, :aria_label, location: :top, match: :prefix]

  @type location :: :top | :bottom
  @type match :: :exact | :prefix

  @type t :: %__MODULE__{
          id: atom(),
          label: String.t(),
          to: String.t(),
          icon: String.t() | nil,
          aria_label: String.t() | nil,
          location: location(),
          match: match()
        }
end

defmodule JidoHubWeb.Menus do
  @moduledoc """
  Centralizes menu item configuration for all layouts.
  Provides menu items for public and dashboard contexts.
  """

  alias JidoHubWeb.Menus.MenuItem

  @doc """
  Returns menu items for the specified context.
  """
  @spec items(:public | :dashboard | :settings | :admin) :: [MenuItem.t()]
  def items(:public), do: public_items()
  def items(:dashboard), do: dashboard_items()
  def items(:settings), do: settings_items()
  def items(:admin), do: admin_items()

  @doc """
  Returns menu items for the public layout.
  """
  @spec public_items() :: [MenuItem.t()]
  def public_items do
    [
      %MenuItem{
        id: :home,
        label: "Home",
        to: "/",
        aria_label: "Home",
        match: :exact
      },
      %MenuItem{
        id: :features,
        label: "Features",
        to: "/features",
        aria_label: "Features"
      },
      %MenuItem{
        id: :integrations,
        label: "Integrations",
        to: "/integrations",
        aria_label: "Integrations"
      },
      %MenuItem{
        id: :pricing,
        label: "Pricing",
        to: "/pricing",
        aria_label: "Pricing"
      },
      %MenuItem{
        id: :faq,
        label: "FAQ",
        to: "/faq",
        aria_label: "FAQ"
      }
    ]
  end

  @doc """
  Returns menu items for the dashboard layout.
  """
  @spec dashboard_items() :: [MenuItem.t()]
  def dashboard_items do
    [
      %MenuItem{
        id: :home,
        label: "Home",
        icon: "hero-home",
        to: "/",
        aria_label: "Home",
        match: :exact
      },
      %MenuItem{
        id: :workflows,
        label: "Workflows",
        icon: "hero-bolt",
        to: "/workflows",
        aria_label: "Workflows"
      },
      %MenuItem{
        id: :agents,
        label: "Agents",
        icon: "hero-cpu-chip",
        to: "/agents",
        aria_label: "Agents"
      },
      %MenuItem{
        id: :data,
        label: "Data",
        icon: "hero-table-cells",
        to: "/data",
        aria_label: "Data"
      },
      %MenuItem{
        id: :settings,
        label: "Settings",
        icon: "hero-cog-6-tooth",
        to: "/settings",
        aria_label: "Settings",
        location: :bottom
      }
    ]
  end

  @doc """
  Returns menu items for the settings pages.
  """
  @spec settings_items() :: [MenuItem.t()]
  def settings_items do
    [
      %MenuItem{
        id: :preferences,
        label: "Preferences",
        icon: "hero-adjustments-horizontal",
        to: "/settings",
        aria_label: "Preferences",
        match: :exact
      },
      %MenuItem{
        id: :profile,
        label: "Profile",
        icon: "hero-user-circle",
        to: "/settings/profile",
        aria_label: "Profile"
      },
      %MenuItem{
        id: :security,
        label: "Security",
        icon: "hero-shield-check",
        to: "/settings/security",
        aria_label: "Security"
      }
    ]
  end

  @doc """
  Returns menu items for the admin layout.
  """
  @spec admin_items() :: [MenuItem.t()]
  def admin_items do
    [
      %MenuItem{
        id: :overview,
        label: "Overview",
        icon: "hero-home",
        to: "/admin",
        aria_label: "Admin Overview",
        match: :exact
      },
      %MenuItem{
        id: :users,
        label: "Users",
        icon: "hero-users",
        to: "/admin/users",
        aria_label: "Users"
      },
      %MenuItem{
        id: :organizations,
        label: "Organizations",
        icon: "hero-building-office-2",
        to: "/admin/organizations",
        aria_label: "Organizations"
      },
      %MenuItem{
        id: :analytics,
        label: "Analytics",
        icon: "hero-chart-bar",
        to: "/admin/analytics",
        aria_label: "Analytics"
      },
      %MenuItem{
        id: :logs,
        label: "Logs",
        icon: "hero-queue-list",
        to: "/admin/logs",
        aria_label: "Logs"
      },
      %MenuItem{
        id: :system_settings,
        label: "System Settings",
        icon: "hero-cog-8-tooth",
        to: "/admin/settings",
        aria_label: "System Settings",
        location: :bottom
      }
    ]
  end

  @doc """
  Groups menu items by location (top or bottom).
  Useful for dashboard layout with icon rail navigation.
  """
  @spec group_by_location([MenuItem.t()]) :: %{top: [MenuItem.t()], bottom: [MenuItem.t()]}
  def group_by_location(items) do
    Enum.group_by(items, & &1.location)
  end

  @doc """
  Checks if a menu item is active based on the current path.
  Uses exact or prefix matching based on the item's match setting.
  """
  @spec active?(String.t(), MenuItem.t()) :: boolean()
  def active?(current_path, %MenuItem{to: to, match: :exact}), do: current_path == to

  def active?(current_path, %MenuItem{to: to, match: :prefix}),
    do: String.starts_with?(current_path, to)
end
