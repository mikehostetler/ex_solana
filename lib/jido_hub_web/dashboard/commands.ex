defmodule JidoHubWeb.Dashboard.Command do
  @moduledoc """
  Represents a single command in the command palette.
  """

  @enforce_keys [:id, :label]
  defstruct [:id, :label, :group, :shortcut, :icon, :meta, :action]

  @type action ::
          {:navigate, String.t()}
          | {:live_event, String.t()}
          | {:live_event, String.t(), map()}
          | {:js, Phoenix.LiveView.JS.t()}

  @type t :: %__MODULE__{
          id: atom(),
          label: String.t(),
          group: String.t() | nil,
          shortcut: String.t() | nil,
          icon: String.t() | nil,
          meta: map() | nil,
          action: action() | nil
        }
end

defmodule JidoHubWeb.Dashboard.Commands do
  @moduledoc """
  Centralizes command palette configuration.
  Provides default commands for the application.
  """

  alias JidoHubWeb.Dashboard.Command

  @doc """
  Returns the default command palette commands.
  """
  @spec default() :: [Command.t()]
  def default do
    [
      %Command{
        id: :new_workflow,
        label: "Create new workflow",
        group: "Workflows",
        icon: "hero-plus",
        shortcut: "⌘N",
        action: {:live_event, "new_workflow"}
      },
      %Command{
        id: :search_workflows,
        label: "Search workflows",
        group: "Workflows",
        icon: "hero-magnifying-glass",
        shortcut: "⌘K",
        action: {:live_event, "open_search"}
      },
      %Command{
        id: :goto_workflows,
        label: "Go to Workflows",
        group: "Navigate",
        icon: "hero-bolt",
        action: {:navigate, "/"}
      },
      %Command{
        id: :goto_agents,
        label: "Go to Agents",
        group: "Navigate",
        icon: "hero-cpu-chip",
        action: {:navigate, "/agents"}
      },
      %Command{
        id: :goto_data,
        label: "Go to Data",
        group: "Navigate",
        icon: "hero-table-cells",
        action: {:navigate, "/data"}
      },
      %Command{
        id: :goto_settings,
        label: "Open settings",
        group: "Navigate",
        icon: "hero-cog-6-tooth",
        shortcut: "⌘,",
        action: {:navigate, "/settings"}
      },
      %Command{
        id: :toggle_theme,
        label: "Change theme",
        group: "View",
        icon: "hero-swatch",
        action: {:live_event, "toggle_theme"}
      },
      %Command{
        id: :help,
        label: "Help & documentation",
        group: "Support",
        icon: "hero-question-mark-circle",
        action: {:live_event, "show_help"}
      }
    ]
  end

  @doc """
  Groups commands by their group name.
  """
  @spec group_by_category([Command.t()]) :: %{String.t() => [Command.t()]}
  def group_by_category(commands) do
    Enum.group_by(commands, fn cmd -> cmd.group || "Other" end)
  end

  @doc """
  Filters commands by a search query (case-insensitive).
  """
  @spec filter(String.t(), [Command.t()]) :: [Command.t()]
  def filter("", commands), do: commands

  def filter(query, commands) do
    query_lower = String.downcase(query)

    Enum.filter(commands, fn cmd ->
      String.contains?(String.downcase(cmd.label), query_lower)
    end)
  end
end
