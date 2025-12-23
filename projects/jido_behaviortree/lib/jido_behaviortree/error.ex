defmodule Jido.BehaviorTree.Error do
  @moduledoc """
  Centralized error handling for Jido BehaviorTree using Splode.

  Provides two error classes:
  - `:invalid` - Validation and configuration errors
  - `:execution` - Runtime execution errors
  """
  use Splode,
    error_classes: [
      invalid: Invalid,
      execution: Execution
    ],
    unknown_error: __MODULE__.UnknownError

  defmodule Invalid do
    @moduledoc "Invalid input/config error class"
    use Splode.ErrorClass, class: :invalid
  end

  defmodule Execution do
    @moduledoc "Execution error class"
    use Splode.ErrorClass, class: :execution
  end

  defmodule BehaviorTreeError do
    @moduledoc "General behavior tree error"
    defexception [:message, :details]

    @type t :: %__MODULE__{message: String.t(), details: map()}

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Behavior tree error"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule UnknownError do
    @moduledoc "Unknown error"
    defexception [:message, :details]

    @type t :: %__MODULE__{message: String.t(), details: map()}

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Unknown error"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  @doc "Creates a validation error with the given message and optional details."
  @spec validation_error(String.t(), map()) :: BehaviorTreeError.t()
  def validation_error(message, details \\ %{}) do
    BehaviorTreeError.exception(message: message, details: Map.put(details, :type, :validation))
  end

  @doc "Creates an execution error with the given message and optional details."
  @spec execution_error(String.t(), map()) :: BehaviorTreeError.t()
  def execution_error(message, details \\ %{}) do
    BehaviorTreeError.exception(message: message, details: Map.put(details, :type, :execution))
  end

  @doc "Creates a node-specific error with the given message, node module, and optional details."
  @spec node_error(String.t(), module(), map()) :: BehaviorTreeError.t()
  def node_error(message, node_module, details \\ %{}) do
    BehaviorTreeError.exception(
      message: message,
      details: Map.merge(details, %{type: :node, node: node_module})
    )
  end
end
