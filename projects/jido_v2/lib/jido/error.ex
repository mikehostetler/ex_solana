defmodule Jido.Error do
  @moduledoc """
  Central error module for Jido v2, built on Splode.

  Use this module to create/aggregate errors across the framework.

  ## Error Classes

  - `:invalid` - Errors caused by invalid input or configuration
  - `:discovery` - Errors related to component discovery and the discovery cache
  - `:framework` - Internal framework errors (unexpected failures / bugs)
  - `:unknown` - Fallback for unknown/unclassified errors

  ## Usage

      # Create an error
      error = Jido.Error.Discovery.CacheInitFailed.exception(reason: :oops)

      # Aggregate multiple errors
      class = Jido.Error.to_class([error1, error2])

      # Unwrap ok/error tuples (raises on error)
      {:ok, value} |> Jido.Error.unwrap!()
  """

  use Splode,
    error_classes: [
      invalid: Jido.Error.Invalid,
      discovery: Jido.Error.Discovery,
      framework: Jido.Error.Framework,
      agent: Jido.Error.Agent,
      unknown: Jido.Error.Unknown
    ],
    unknown_error: Jido.Error.Unknown.Unknown
end

defmodule Jido.Error.Invalid do
  @moduledoc """
  Errors caused by invalid input or configuration.
  """

  use Splode.ErrorClass, class: :invalid
end

defmodule Jido.Error.Discovery do
  @moduledoc """
  Errors related to component discovery and the discovery cache.
  """

  use Splode.ErrorClass, class: :discovery
end

defmodule Jido.Error.Framework do
  @moduledoc """
  Internal framework errors (unexpected failures / bugs).
  """

  use Splode.ErrorClass, class: :framework
end

defmodule Jido.Error.Unknown do
  @moduledoc """
  Fallback error class for unknown/unclassified errors.
  """

  use Splode.ErrorClass, class: :unknown
end

defmodule Jido.Error.Unknown.Unknown do
  @moduledoc """
  Fallback exception used when an error does not fit any known class.
  """

  use Splode.Error, class: :unknown, fields: [:error]

  @impl true
  def message(%{error: error}) do
    if is_binary(error), do: to_string(error), else: inspect(error)
  end
end

defmodule Jido.Error.Discovery.CacheInitFailed do
  @moduledoc """
  Error raised when the discovery cache fails to initialize.
  """

  use Splode.Error, class: :discovery, fields: [:reason]

  @impl true
  def message(%{reason: reason}) do
    "Failed to initialize discovery cache: #{inspect(reason)}"
  end
end

defmodule Jido.Error.Discovery.CacheRefreshFailed do
  @moduledoc """
  Error raised when the discovery cache fails to refresh.
  """

  use Splode.Error, class: :discovery, fields: [:reason]

  @impl true
  def message(%{reason: reason}) do
    "Failed to refresh discovery cache: #{inspect(reason)}"
  end
end

defmodule Jido.Error.Discovery.NotInitialized do
  @moduledoc """
  Error raised when the discovery cache has not been initialized.
  """

  use Splode.Error, class: :discovery, fields: []

  @impl true
  def message(_) do
    "Discovery cache has not been initialized. Call Jido.Discovery.init/0 first."
  end
end

# Agent Errors

defmodule Jido.Error.Agent do
  @moduledoc """
  Errors related to Agent operations.
  """

  use Splode.ErrorClass, class: :agent
end

defmodule Jido.Error.Agent.InvalidState do
  @moduledoc """
  Error raised when agent state validation fails.
  """

  use Splode.Error, class: :agent, fields: [:reason, :agent]

  @impl true
  def message(%{reason: reason, agent: agent}) do
    "Agent state validation failed for #{inspect(agent)}: #{inspect(reason)}"
  end

  def message(%{reason: reason}) do
    "Agent state validation failed: #{inspect(reason)}"
  end
end

defmodule Jido.Error.Agent.InvalidSignal do
  @moduledoc """
  Error raised when an invalid signal is received.
  """

  use Splode.Error, class: :agent, fields: [:reason, :signal]

  @impl true
  def message(%{reason: reason, signal: signal}) do
    "Invalid signal #{inspect(signal)}: #{inspect(reason)}"
  end

  def message(%{reason: reason}) do
    "Invalid signal: #{inspect(reason)}"
  end
end

defmodule Jido.Error.Agent.UnhandledSignal do
  @moduledoc """
  Error raised when an agent receives a signal it cannot handle.
  """

  use Splode.Error, class: :agent, fields: [:signal_type, :agent]

  @impl true
  def message(%{signal_type: signal_type, agent: agent}) do
    "Agent #{inspect(agent)} cannot handle signal type: #{inspect(signal_type)}"
  end

  def message(%{signal_type: signal_type}) do
    "Unhandled signal type: #{inspect(signal_type)}"
  end
end

defmodule Jido.Error.Agent.RunnerCallbackError do
  @moduledoc """
  Error raised when a runner or agent callback crashes or returns an invalid result.
  """

  use Splode.Error, class: :agent, fields: [:agent, :runner, :reason]

  @impl true
  def message(%{agent: agent, runner: runner, reason: reason}) do
    base = "Runner #{inspect(runner)} failed while invoking #{inspect(agent)}.handle_signal/2"

    cond do
      is_exception(reason) -> base <> ": " <> Exception.message(reason)
      true -> base <> ": " <> inspect(reason)
    end
  end
end

# Invalid Errors

defmodule Jido.Error.Invalid.RunnerConfig do
  @moduledoc """
  Error raised when an agent has an invalid or unsupported runner configuration.
  """

  use Splode.Error, class: :invalid, fields: [:agent, :runner, :reason]

  @impl true
  def message(%{agent: agent, runner: runner, reason: reason}) when not is_nil(agent) do
    "Invalid runner configuration #{inspect(runner)} for agent #{inspect(agent)}: #{inspect(reason)}"
  end

  def message(%{runner: runner, reason: reason}) do
    "Invalid runner configuration #{inspect(runner)}: #{inspect(reason)}"
  end
end

# Framework Errors

defmodule Jido.Error.Framework.UnexpectedRunnerResult do
  @moduledoc """
  Error raised when a runner returns a result that does not match the contract.
  """

  use Splode.Error, class: :framework, fields: [:agent, :runner, :result]

  @impl true
  def message(%{agent: agent, runner: runner, result: result}) do
    "Runner #{inspect(runner)} for agent #{inspect(agent)} returned an invalid result: #{inspect(result)}"
  end
end
