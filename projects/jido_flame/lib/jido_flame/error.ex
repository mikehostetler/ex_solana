defmodule JidoFlame.Error do
  @moduledoc """
  Centralized error handling for JidoFlame using Splode.

  This module provides consistent error creation and handling for FLAME
  remote execution operations.

  ## Error Classes

  Errors are organized into the following classes, in order of precedence:

  - `:invalid` - Invalid configuration, parameters, or directive fields
  - `:execution` - Runtime execution errors from FLAME operations
  - `:remote` - Remote agent lifecycle errors (spawn, stop, communication)
  - `:timeout` - FLAME call and placement timeouts
  - `:internal` - Unexpected internal errors

  ## Usage

      # Create a validation error
      {:error, error} = JidoFlame.Error.validation_error("Invalid pool name", field: :pool)

      # Create a remote call error
      {:error, error} = JidoFlame.Error.remote_call_error("FLAME call failed", pool: MyPool, cause: reason)

      # Create a remote agent error
      {:error, error} = JidoFlame.Error.remote_agent_error("Failed to spawn", agent_id: "agent-1", tag: :worker)
  """
  use Splode,
    error_classes: [
      invalid: Invalid,
      execution: Execution,
      remote: Remote,
      timeout: Timeout,
      internal: Internal
    ],
    unknown_error: JidoFlame.Error.Internal.UnknownError

  defmodule Invalid do
    @moduledoc "Invalid input error class"
    use Splode.ErrorClass, class: :invalid
  end

  defmodule Execution do
    @moduledoc "Execution error class"
    use Splode.ErrorClass, class: :execution
  end

  defmodule Remote do
    @moduledoc "Remote agent error class"
    use Splode.ErrorClass, class: :remote
  end

  defmodule Timeout do
    @moduledoc "Timeout error class"
    use Splode.ErrorClass, class: :timeout
  end

  defmodule Internal do
    @moduledoc "Internal error class"
    use Splode.ErrorClass, class: :internal

    defmodule UnknownError do
      @moduledoc "Unknown internal error"
      defexception [:message, :details]

      @impl true
      def exception(opts) do
        %__MODULE__{
          message: Keyword.get(opts, :message, "Unknown error"),
          details: Keyword.get(opts, :details, %{})
        }
      end
    end
  end

  defmodule InvalidInputError do
    @moduledoc "Error for invalid input parameters or directive fields"
    defexception [:message, :field, :value, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Invalid input"),
        field: Keyword.get(opts, :field),
        value: Keyword.get(opts, :value),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule ConfigError do
    @moduledoc "Error for invalid configuration"
    defexception [:message, :key, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Invalid configuration"),
        key: Keyword.get(opts, :key),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule RemoteCallError do
    @moduledoc "Error for FLAME.call/3 failures"
    defexception [:message, :pool, :cause, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Remote call failed"),
        pool: Keyword.get(opts, :pool),
        cause: Keyword.get(opts, :cause),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule RemoteCastError do
    @moduledoc "Error for FLAME.cast/3 failures"
    defexception [:message, :pool, :cause, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Remote cast failed"),
        pool: Keyword.get(opts, :pool),
        cause: Keyword.get(opts, :cause),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule RemoteAgentError do
    @moduledoc "Error for remote agent spawn/stop failures"
    defexception [:message, :agent_id, :tag, :cause, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Remote agent operation failed"),
        agent_id: Keyword.get(opts, :agent_id),
        tag: Keyword.get(opts, :tag),
        cause: Keyword.get(opts, :cause),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule PlacementError do
    @moduledoc "Error for FLAME.place_child/3 failures"
    defexception [:message, :pool, :child_spec, :cause, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Remote child placement failed"),
        pool: Keyword.get(opts, :pool),
        child_spec: Keyword.get(opts, :child_spec),
        cause: Keyword.get(opts, :cause),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule TimeoutError do
    @moduledoc "Error for FLAME operation timeouts"
    defexception [:message, :timeout, :operation, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Operation timed out"),
        timeout: Keyword.get(opts, :timeout),
        operation: Keyword.get(opts, :operation),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule OwnerError do
    @moduledoc "Error for Owner process failures"
    defexception [:message, :agent_id, :tag, :cause, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Owner process error"),
        agent_id: Keyword.get(opts, :agent_id),
        tag: Keyword.get(opts, :tag),
        cause: Keyword.get(opts, :cause),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule RegistryError do
    @moduledoc "Error for registry lookup/registration failures"
    defexception [:message, :registry, :key, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Registry operation failed"),
        registry: Keyword.get(opts, :registry),
        key: Keyword.get(opts, :key),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule InternalError do
    @moduledoc "Error for unexpected internal failures"
    defexception [:message, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Internal error"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  @doc "Creates a validation error for invalid input parameters"
  def validation_error(message, details \\ %{}) do
    InvalidInputError.exception(
      message: message,
      field: details[:field],
      value: details[:value],
      details: details
    )
  end

  @doc "Creates a configuration error"
  def config_error(message, details \\ %{}) do
    ConfigError.exception(
      message: message,
      key: details[:key],
      details: details
    )
  end

  @doc "Creates a remote call error"
  def remote_call_error(message, details \\ %{}) do
    RemoteCallError.exception(
      message: message,
      pool: details[:pool],
      cause: details[:cause],
      details: details
    )
  end

  @doc "Creates a remote cast error"
  def remote_cast_error(message, details \\ %{}) do
    RemoteCastError.exception(
      message: message,
      pool: details[:pool],
      cause: details[:cause],
      details: details
    )
  end

  @doc "Creates a remote agent error"
  def remote_agent_error(message, details \\ %{}) do
    RemoteAgentError.exception(
      message: message,
      agent_id: details[:agent_id],
      tag: details[:tag],
      cause: details[:cause],
      details: details
    )
  end

  @doc "Creates a placement error"
  def placement_error(message, details \\ %{}) do
    PlacementError.exception(
      message: message,
      pool: details[:pool],
      child_spec: details[:child_spec],
      cause: details[:cause],
      details: details
    )
  end

  @doc "Creates a timeout error"
  def timeout_error(message, details \\ %{}) do
    TimeoutError.exception(
      message: message,
      timeout: details[:timeout],
      operation: details[:operation],
      details: details
    )
  end

  @doc "Creates an owner error"
  def owner_error(message, details \\ %{}) do
    OwnerError.exception(
      message: message,
      agent_id: details[:agent_id],
      tag: details[:tag],
      cause: details[:cause],
      details: details
    )
  end

  @doc "Creates a registry error"
  def registry_error(message, details \\ %{}) do
    RegistryError.exception(
      message: message,
      registry: details[:registry],
      key: details[:key],
      details: details
    )
  end

  @doc "Creates an internal error"
  def internal_error(message, details \\ %{}) do
    InternalError.exception(
      message: message,
      details: details
    )
  end

  @doc """
  Formats a Zoi validation error for pretty printing.
  """
  def format_zoi_error(errors) when is_list(errors) do
    Zoi.prettify_errors(errors)
  end

  def format_zoi_error(error), do: inspect(error)
end
