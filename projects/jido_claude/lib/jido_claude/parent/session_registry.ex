defmodule JidoClaude.Parent.SessionRegistry do
  @moduledoc """
  State helpers for managing multiple Claude sessions in a parent agent.

  The SessionRegistry provides pure functions for managing a `sessions` map
  in the parent agent's state. Each session is tracked by its `session_id`.

  ## Session Structure

      %{
        "session-123" => %{
          status: :running,
          started_at: ~U[2024-01-15 10:30:00Z],
          prompt: "Analyze the codebase...",
          model: "sonnet",
          turns: 5,
          last_activity: ~U[2024-01-15 10:31:23Z],
          child_pid: #PID<0.234.0>,
          meta: %{}
        }
      }

  ## Usage

      state = SessionRegistry.init_sessions(agent.state)
      state = SessionRegistry.register_session(state, "session-123", %{prompt: "..."})
      state = SessionRegistry.update_session(state, "session-123", %{turns: 5})

  """

  @doc """
  Initialize the sessions map if not present.
  """
  def init_sessions(state) do
    Map.put_new(state, :sessions, %{})
  end

  @doc """
  Register a new session in the registry.
  """
  def register_session(state, session_id, attrs) do
    session =
      Map.merge(
        %{
          status: :starting,
          started_at: DateTime.utc_now(),
          turns: 0,
          last_activity: DateTime.utc_now()
        },
        attrs
      )

    put_in(state, [:sessions, session_id], session)
  end

  @doc """
  Update an existing session's attributes.
  Automatically updates `last_activity` timestamp.
  """
  def update_session(state, session_id, updates) do
    update_in(state, [:sessions, session_id], fn session ->
      session
      |> Map.merge(updates)
      |> Map.put(:last_activity, DateTime.utc_now())
    end)
  end

  @doc """
  Get a session by ID.
  """
  def get_session(state, session_id) do
    get_in(state, [:sessions, session_id])
  end

  @doc """
  Remove a session from the registry.
  """
  def remove_session(state, session_id) do
    update_in(state, [:sessions], &Map.delete(&1, session_id))
  end

  @doc """
  Get all active sessions (status: :starting or :running).
  """
  def active_sessions(state) do
    sessions = state[:sessions] || %{}

    sessions
    |> Enum.filter(fn {_id, s} -> s.status in [:starting, :running] end)
    |> Map.new()
  end

  @doc """
  Get all completed sessions (status: :success, :failure, or :cancelled).
  """
  def completed_sessions(state) do
    sessions = state[:sessions] || %{}

    sessions
    |> Enum.filter(fn {_id, s} -> s.status in [:success, :failure, :cancelled] end)
    |> Map.new()
  end

  @doc """
  Count active sessions.
  """
  def count_active(state) do
    active_sessions(state) |> map_size()
  end

  @doc """
  Count sessions by status.
  """
  def count_by_status(state) do
    sessions = state[:sessions] || %{}

    sessions
    |> Enum.group_by(fn {_id, s} -> s.status end)
    |> Enum.map(fn {status, list} -> {status, length(list)} end)
    |> Map.new()
  end

  @doc """
  Calculate total cost across all sessions.
  """
  def total_cost(state) do
    sessions = state[:sessions] || %{}

    sessions
    |> Enum.map(fn {_id, s} -> s[:cost_usd] || 0.0 end)
    |> Enum.sum()
  end

  @doc """
  Find sessions by metadata key/value.
  """
  def find_by_meta(state, key, value) do
    sessions = state[:sessions] || %{}

    sessions
    |> Enum.filter(fn {_id, s} -> get_in(s, [:meta, key]) == value end)
    |> Map.new()
  end
end
