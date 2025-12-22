defmodule JidoCode.Test.SessionSupervisorStub do
  @moduledoc """
  Test stub for JidoCode.Session.Supervisor.

  This module simulates the per-session supervisor behavior for testing
  SessionSupervisor.start_session/1 and stop_session/1 before the real
  Session.Supervisor is implemented (Task 1.4.1).

  The stub:
  - Accepts `session: session` option like the real supervisor will
  - Registers in SessionProcessRegistry with {:session, session_id} key
  - Is a simple GenServer that can be started/stopped
  """

  use GenServer

  @registry JidoCode.SessionProcessRegistry

  @doc """
  Starts the stub supervisor.

  ## Options

  - `:session` - (required) The session struct
  """
  def start_link(opts) do
    session = Keyword.fetch!(opts, :session)
    name = via(session.id)
    GenServer.start_link(__MODULE__, session, name: name)
  end

  @doc """
  Returns the child_spec for this module.

  This is required for DynamicSupervisor.start_child/2 to work.
  """
  def child_spec(opts) do
    session = Keyword.fetch!(opts, :session)

    %{
      id: {:session_supervisor, session.id},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :temporary
    }
  end

  # Registry via tuple for process naming
  defp via(session_id) do
    {:via, Registry, {@registry, {:session, session_id}}}
  end

  # GenServer callbacks

  @impl true
  def init(session) do
    {:ok, %{session: session}}
  end

  @impl true
  def handle_call(:get_session, _from, state) do
    {:reply, state.session, state}
  end
end
