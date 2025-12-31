defmodule Jido.Skill.Spec do
  @moduledoc """
  The normalized representation of a skill attached to an agent.

  Contains all metadata needed to integrate a skill with an agent,
  including actions, schema, configuration, and signal patterns.
  """

  @type t :: %__MODULE__{
          module: module(),
          name: String.t(),
          state_key: atom(),
          description: String.t() | nil,
          category: String.t() | nil,
          vsn: String.t() | nil,
          schema: any(),
          config_schema: any(),
          config: map(),
          signal_patterns: [String.t()],
          tags: [String.t()],
          actions: [module()]
        }

  @enforce_keys [:module, :name, :state_key, :actions]
  defstruct [
    :module,
    :name,
    :state_key,
    :description,
    :category,
    :vsn,
    :schema,
    :config_schema,
    config: %{},
    signal_patterns: [],
    tags: [],
    actions: []
  ]
end
