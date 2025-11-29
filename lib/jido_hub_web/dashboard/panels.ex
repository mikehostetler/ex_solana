defmodule JidoHubWeb.Dashboard.Panel do
  @moduledoc """
  Configuration for a single resizable panel in the dashboard layout.
  """

  @enforce_keys [:var, :min, :max, :default, :open]
  defstruct [:var, :min, :max, :default, :open]

  @type t :: %__MODULE__{
          var: String.t(),
          min: integer(),
          max: integer(),
          default: integer(),
          open: boolean()
        }
end

defmodule JidoHubWeb.Dashboard.PanelSet do
  @moduledoc """
  Complete configuration for all dashboard panels.
  """

  alias JidoHubWeb.Dashboard.Panel

  @enforce_keys [:storage_key, :left, :right, :bottom]
  defstruct [:storage_key, :left, :right, :bottom]

  @type t :: %__MODULE__{
          storage_key: String.t(),
          left: Panel.t(),
          right: Panel.t(),
          bottom: Panel.t()
        }
end

defmodule JidoHubWeb.Dashboard.Panels do
  @moduledoc """
  Centralizes panel configuration for the dashboard layout.
  Provides default panel sizes, min/max constraints, and initial states.
  """

  alias JidoHubWeb.Dashboard.{Panel, PanelSet}

  @doc """
  Returns the default panel configuration for the main dashboard.
  """
  @spec default() :: PanelSet.t()
  def default do
    %PanelSet{
      storage_key: "jidohub:dashboard:v1",
      left: %Panel{
        var: "--left",
        min: 200,
        max: 600,
        default: 240,
        open: true
      },
      right: %Panel{
        var: "--right",
        min: 280,
        max: 600,
        default: 360,
        open: true
      },
      bottom: %Panel{
        var: "--bottom",
        min: 150,
        max: 600,
        default: 240,
        open: true
      }
    }
  end

  @doc """
  Returns panel configuration specific to the workflows route.
  """
  @spec workflows() :: PanelSet.t()
  def workflows do
    %PanelSet{
      storage_key: "jidohub:workflows:v1",
      left: %Panel{
        var: "--left",
        min: 200,
        max: 600,
        default: 240,
        open: true
      },
      right: %Panel{
        var: "--right",
        min: 280,
        max: 600,
        default: 360,
        open: true
      },
      bottom: %Panel{
        var: "--bottom",
        min: 150,
        max: 600,
        default: 240,
        open: true
      }
    }
  end
end
