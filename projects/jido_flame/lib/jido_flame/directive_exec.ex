defmodule JidoFlame.DirectiveExec do
  @moduledoc """
  Executes FLAME-related directives.

  This module provides the runtime execution logic for JidoFlame directives.
  Each directive type is pattern-matched and executed using the appropriate
  FLAME function.

  ## Usage

  Typically called by Jido's directive execution engine:

      directive = %JidoFlame.Directive.RemoteCall{pool: MyPool, fun: fn -> :result end}
      {:ok, result} = JidoFlame.DirectiveExec.exec(directive, context)

  ## Context

  The context map may contain:
  - `:logical_agent_id` - ID of the executing agent (required for SpawnRemoteAgent)
  - `:default_pool` - Fallback FLAME pool if none specified
  """

  require Logger

  alias JidoFlame.{Error, Owner}

  alias JidoFlame.Directive.{
    RemoteCall,
    RemoteCast,
    PlaceRemoteChild,
    SpawnRemoteAgent,
    StopRemoteAgent
  }

  @type context :: %{
          optional(:logical_agent_id) => term(),
          optional(:default_pool) => atom(),
          optional(atom()) => term()
        }

  @type exec_result ::
          {:ok, term()}
          | {:ok, term(), [Jido.Signal.t()]}
          | {:error, Exception.t()}

  @doc """
  Executes a JidoFlame directive.

  ## Parameters

  - `directive` - A JidoFlame directive struct
  - `context` - Execution context map

  ## Returns

  - `{:ok, result}` - Successful execution with result
  - `{:ok, result, signals}` - Successful execution with result and signals to emit
  - `{:error, exception}` - Execution failed

  ## Examples

      iex> directive = RemoteCall.new!(%{pool: MyPool, fun: fn -> 1 + 1 end})
      iex> DirectiveExec.exec(directive, %{})
      {:ok, 2}
  """
  @spec exec(struct(), context()) :: exec_result()
  def exec(%RemoteCall{} = d, ctx), do: exec_remote_call(d, ctx)
  def exec(%RemoteCast{} = d, ctx), do: exec_remote_cast(d, ctx)
  def exec(%PlaceRemoteChild{} = d, ctx), do: exec_place_remote_child(d, ctx)
  def exec(%SpawnRemoteAgent{} = d, ctx), do: exec_spawn_remote_agent(d, ctx)
  def exec(%StopRemoteAgent{} = d, ctx), do: exec_stop_remote_agent(d, ctx)

  def exec(unknown, _ctx) do
    {:error, Error.validation_error("Unknown directive type: #{inspect(unknown.__struct__)}")}
  end

  # RemoteCall - FLAME.call/3

  defp exec_remote_call(%RemoteCall{} = d, ctx) do
    pool = d.pool || ctx[:default_pool]

    unless pool do
      throw({:missing_field, :pool, "No FLAME pool specified"})
    end

    Logger.debug("[JidoFlame] Executing RemoteCall on pool #{inspect(pool)}")

    try do
      result = FLAME.call(pool, d.fun, d.opts)

      case d.result_type do
        nil ->
          {:ok, wrap_result(result, d)}

        type ->
          signal = build_result_signal(type, result, d)
          {:ok, wrap_result(result, d), [signal]}
      end
    rescue
      e in [RuntimeError, ArgumentError] ->
        {:error, Error.remote_call_error(Exception.message(e), pool: pool, cause: e)}
    catch
      :exit, reason ->
        {:error, Error.remote_call_error("FLAME call exited: #{inspect(reason)}", pool: pool, cause: reason)}

      {:missing_field, field, message} ->
        {:error, Error.validation_error(message, field: field)}
    end
  end

  # RemoteCast - FLAME.cast/3

  defp exec_remote_cast(%RemoteCast{} = d, ctx) do
    pool = d.pool || ctx[:default_pool]

    unless pool do
      throw({:missing_field, :pool, "No FLAME pool specified"})
    end

    Logger.debug("[JidoFlame] Executing RemoteCast on pool #{inspect(pool)}")

    try do
      FLAME.cast(pool, d.fun, d.opts)
      {:ok, wrap_result(:ok, d)}
    rescue
      e ->
        {:error, Error.remote_cast_error(Exception.message(e), pool: pool, cause: e)}
    catch
      :exit, reason ->
        {:error, Error.remote_cast_error("FLAME cast exited: #{inspect(reason)}", pool: pool, cause: reason)}

      {:missing_field, field, message} ->
        {:error, Error.validation_error(message, field: field)}
    end
  end

  # PlaceRemoteChild - FLAME.place_child/3 (generic)

  defp exec_place_remote_child(%PlaceRemoteChild{} = d, ctx) do
    pool = d.pool || ctx[:default_pool]

    unless pool do
      throw({:missing_field, :pool, "No FLAME pool specified"})
    end

    Logger.debug("[JidoFlame] Executing PlaceRemoteChild on pool #{inspect(pool)}")

    try do
      case FLAME.place_child(pool, d.child_spec, d.opts) do
        {:ok, pid} ->
          result = %{
            pid: pid,
            node: node(pid),
            tag: d.tag,
            tracked: d.track?
          }

          {:ok, wrap_result(result, d)}

        {:error, reason} ->
          {:error,
           Error.placement_error("Failed to place child",
             pool: pool,
             child_spec: d.child_spec,
             cause: reason
           )}
      end
    rescue
      e ->
        {:error,
         Error.placement_error(Exception.message(e),
           pool: pool,
           child_spec: d.child_spec,
           cause: e
         )}
    catch
      :exit, reason ->
        {:error,
         Error.placement_error("FLAME placement exited: #{inspect(reason)}",
           pool: pool,
           cause: reason
         )}

      {:missing_field, field, message} ->
        {:error, Error.validation_error(message, field: field)}
    end
  end

  # SpawnRemoteAgent - Uses Owner pattern for Jido agents

  defp exec_spawn_remote_agent(%SpawnRemoteAgent{} = d, ctx) do
    pool = d.pool || ctx[:default_pool]
    logical_agent_id = ctx[:logical_agent_id]

    unless pool do
      throw({:missing_field, :pool, "No FLAME pool specified"})
    end

    unless logical_agent_id do
      throw({:missing_field, :logical_agent_id, "No logical_agent_id in context"})
    end

    Logger.debug(
      "[JidoFlame] Spawning remote agent #{inspect(d.agent)} on pool #{inspect(pool)} " <>
        "for parent #{inspect(logical_agent_id)}, tag #{inspect(d.tag)}"
    )

    child_spec = build_agent_child_spec(d, logical_agent_id)

    try do
      case Owner.start_child(logical_agent_id, d.tag, child_spec, pool,
             flame_opts: d.flame_opts,
             meta: d.meta
           ) do
        {:ok, owner_pid, child_pid} ->
          result = %{
            owner_pid: owner_pid,
            child_pid: child_pid,
            node: node(child_pid),
            tag: d.tag,
            agent: d.agent,
            remote?: true
          }

          signal = build_agent_signal("jido.flame.remote.agent.started", result, d)
          {:ok, result, [signal]}

        {:error, reason} ->
          error =
            Error.remote_agent_error(
              "Failed to spawn remote agent",
              agent_id: logical_agent_id,
              tag: d.tag,
              cause: reason
            )

          {:error, error}
      end
    catch
      {:missing_field, field, message} ->
        {:error, Error.validation_error(message, field: field)}
    end
  end

  # StopRemoteAgent - Stop via Owner

  defp exec_stop_remote_agent(%StopRemoteAgent{} = d, ctx) do
    logical_agent_id = ctx[:logical_agent_id]

    unless logical_agent_id do
      throw({:missing_field, :logical_agent_id, "No logical_agent_id in context"})
    end

    Logger.debug("[JidoFlame] Stopping remote agent for parent #{inspect(logical_agent_id)}, tag #{inspect(d.tag)}")

    try do
      case Owner.stop_child(logical_agent_id, d.tag, d.reason) do
        :ok ->
          result = %{
            tag: d.tag,
            reason: d.reason,
            stopped: true
          }

          signal = build_agent_signal("jido.flame.remote.agent.stopped", result, d)
          {:ok, result, [signal]}

        {:error, :not_found} ->
          {:error,
           Error.remote_agent_error(
             "Remote agent not found",
             agent_id: logical_agent_id,
             tag: d.tag
           )}
      end
    catch
      {:missing_field, field, message} ->
        {:error, Error.validation_error(message, field: field)}
    end
  end

  # Helpers

  defp wrap_result(result, directive) do
    case directive do
      %{tag: tag} when not is_nil(tag) ->
        %{result: result, tag: tag}

      _ ->
        %{result: result}
    end
  end

  defp build_result_signal(type, result, directive) do
    Jido.Signal.new!(type, %{result: result, tag: directive.tag},
      source: "jido_flame",
      datacontenttype: "application/json"
    )
  end

  defp build_agent_signal(type, data, _directive) do
    Jido.Signal.new!(type, data,
      source: "jido_flame",
      datacontenttype: "application/json"
    )
  end

  defp build_agent_child_spec(directive, logical_agent_id) do
    agent_opts =
      Map.merge(directive.opts, %{
        parent_ref: %{
          logical_agent_id: logical_agent_id,
          owner_pid: nil,
          meta: directive.meta
        }
      })

    case directive.agent do
      module when is_atom(module) ->
        {module, agent_opts}

      %{} = struct ->
        {JidoFlame.AgentStarter, {struct, agent_opts}}
    end
  end
end
