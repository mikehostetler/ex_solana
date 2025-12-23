defmodule Jido.BehaviorTree.Nodes.Succeeder do
  @moduledoc """
  A decorator node that always returns success when its child completes.

  - If child returns `:success` or `:failure`, succeeder returns `:success`
  - If child returns `:running`, succeeder returns `:running`
  - Errors are passed through unchanged

  ## Example

      succeeder = Succeeder.new(risky_action)
      # Always succeeds even if risky_action fails

  """

  alias Jido.BehaviorTree.Node

  @schema Zoi.struct(
            __MODULE__,
            %{
              child: Zoi.any(description: "The child node to wrap")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for this module"
  def schema, do: @schema

  @behaviour Jido.BehaviorTree.Node

  @doc """
  Creates a new Succeeder node wrapping the given child.

  ## Examples

      iex> Succeeder.new(child_node)
      %Succeeder{child: child_node}

  """
  @spec new(Node.t()) :: t()
  def new(child) do
    %__MODULE__{child: child}
  end

  @impl true
  def tick(%__MODULE__{child: child} = state, tick) do
    {status, updated_child} = Node.execute_tick(child, tick)

    result_status =
      case status do
        :success -> :success
        :failure -> :success
        :running -> :running
        {:error, _} = error -> error
      end

    {result_status, %{state | child: updated_child}}
  end

  @impl true
  def halt(%__MODULE__{child: child} = state) do
    halted_child = Node.execute_halt(child)
    %{state | child: halted_child}
  end
end
