defmodule JidoCode.Agents.TaskAgent do
  @moduledoc """
  GenServer for executing isolated sub-tasks with their own LLM context.

  TaskAgent is spawned by the Task tool to handle complex sub-tasks that
  require their own LLM conversation context. Each TaskAgent runs independently
  and returns results to the parent agent.

  ## Usage

      {:ok, pid} = TaskAgent.start_link(
        task_id: "task_abc123",
        description: "Search for API patterns",
        prompt: "Find all REST API endpoints in the codebase",
        model: :anthropic,
        timeout: 60_000,
        session_id: "session-uuid"  # Optional: for session isolation
      )

      {:ok, result} = TaskAgent.execute(pid)

  ## Session Context

  When a `session_id` is provided, the TaskAgent:
  - Stores the session_id for tool execution context
  - Broadcasts progress to session-specific topics (`tui.events.{session_id}`)
  - Operates within the same security boundary as the parent session

  ## PubSub Integration

  Progress updates are broadcast to `task.{task_id}` topic and optionally
  to `tui.events.{session_id}` when session context is available:

  - `{:task_started, task_id}` - Task execution began
  - `{:task_progress, task_id, message}` - Progress update
  - `{:task_completed, task_id, result}` - Task finished successfully
  - `{:task_failed, task_id, reason}` - Task failed with error
  """

  use GenServer
  require Logger

  alias Jido.AI.Actions.ReqLlm.ChatCompletion
  alias Jido.AI.Model
  alias Jido.AI.Prompt
  alias JidoCode.Config

  @pubsub JidoCode.PubSub
  @default_timeout 60_000

  @task_system_prompt """
  You are a specialized sub-agent executing a specific task within a coding assistant.

  Your focus is narrow - complete only the assigned task and return results concisely.
  Do not ask clarifying questions. Do your best with the information provided.

  Guidelines:
  - Stay focused on the specific task
  - Return results in a clear, structured format
  - If you cannot complete the task, explain what's blocking you
  - Be concise but thorough
  """

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts a TaskAgent with the given specification.

  ## Options

  - `:task_id` - (required) Unique identifier for tracking
  - `:description` - (required) Short task description
  - `:prompt` - (required) Detailed task instructions
  - `:model` - (optional) Override model name
  - `:provider` - (optional) Override provider
  - `:timeout` - (optional) Execution timeout in ms (default 60000)
  - `:session_id` - (optional) Parent session ID for isolation and routing

  ## Returns

  - `{:ok, pid}` - Agent started successfully
  - `{:error, reason}` - Failed to start
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Executes the task and returns the result.

  This is a synchronous call that blocks until the task completes or times out.

  ## Returns

  - `{:ok, result}` - Task completed with result string
  - `{:error, :timeout}` - Task exceeded timeout
  - `{:error, reason}` - Task failed with error
  """
  @spec execute(GenServer.server(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def execute(pid, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(pid, :execute, timeout + 5_000)
  end

  @doc """
  Returns the current status of the task.
  """
  @spec status(GenServer.server()) :: map()
  def status(pid) do
    GenServer.call(pid, :status)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    with {:ok, task_id} <- fetch_required(opts, :task_id),
         {:ok, description} <- fetch_required(opts, :description),
         {:ok, prompt} <- fetch_required(opts, :prompt),
         {:ok, config} <- build_config(opts) do
      # Extract optional session_id for session isolation
      session_id = Keyword.get(opts, :session_id)

      state = %{
        task_id: task_id,
        description: description,
        prompt: prompt,
        config: config,
        timeout: Keyword.get(opts, :timeout, @default_timeout),
        status: :ready,
        result: nil,
        topic: "task.#{task_id}",
        session_id: session_id
      }

      # Emit telemetry for task creation
      :telemetry.execute(
        [:jido_code, :task_agent, :init],
        %{system_time: System.system_time()},
        %{task_id: task_id, description: description, session_id: session_id}
      )

      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp fetch_required(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, "Missing required option: #{key}"}
    end
  end

  @impl true
  def handle_call(:execute, from, %{status: :ready} = state) do
    # Mark as running
    new_state = %{state | status: :running}
    broadcast_started(state.topic, state.task_id, state.session_id)

    # Execute async to not block GenServer
    Task.Supervisor.start_child(JidoCode.TaskSupervisor, fn ->
      result = do_execute_task(new_state)

      # Handle result
      case result do
        {:ok, content} ->
          broadcast_completed(state.topic, state.task_id, content, state.session_id)
          GenServer.reply(from, {:ok, content})

        {:error, reason} ->
          broadcast_failed(state.topic, state.task_id, reason, state.session_id)
          GenServer.reply(from, {:error, reason})
      end
    end)

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:execute, _from, %{status: status} = state) do
    {:reply, {:error, {:invalid_state, status}}, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      task_id: state.task_id,
      description: state.description,
      status: state.status,
      result: state.result,
      session_id: state.session_id
    }

    {:reply, status, state}
  end

  @impl true
  def terminate(_reason, state) do
    :telemetry.execute(
      [:jido_code, :task_agent, :terminate],
      %{system_time: System.system_time()},
      %{task_id: state.task_id, status: state.status}
    )

    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp build_config(opts) do
    case Config.get_llm_config() do
      {:ok, base_config} ->
        config = %{
          provider: Keyword.get(opts, :provider, base_config.provider),
          model: Keyword.get(opts, :model, base_config.model),
          temperature: Keyword.get(opts, :temperature, 0.3),
          max_tokens: Keyword.get(opts, :max_tokens, 2048)
        }

        {:ok, config}

      {:error, _reason} = error ->
        # Require explicit provider/model if no base config
        if Keyword.has_key?(opts, :provider) and Keyword.has_key?(opts, :model) do
          config = %{
            provider: Keyword.fetch!(opts, :provider),
            model: Keyword.fetch!(opts, :model),
            temperature: Keyword.get(opts, :temperature, 0.3),
            max_tokens: Keyword.get(opts, :max_tokens, 2048)
          }

          {:ok, config}
        else
          error
        end
    end
  end

  defp do_execute_task(state) do
    model_tuple =
      {state.config.provider,
       [
         model: state.config.model,
         temperature: state.config.temperature,
         max_tokens: state.config.max_tokens
       ]}

    with {:ok, model} <- Model.from(model_tuple),
         {:ok, response} <- run_chat(model, state) do
      :telemetry.execute(
        [:jido_code, :task_agent, :complete],
        %{system_time: System.system_time()},
        %{task_id: state.task_id, success: true}
      )

      {:ok, response}
    else
      {:error, reason} = error ->
        Logger.error("TaskAgent #{state.task_id} failed: #{inspect(reason)}")

        :telemetry.execute(
          [:jido_code, :task_agent, :complete],
          %{system_time: System.system_time()},
          %{task_id: state.task_id, success: false, error: reason}
        )

        error
    end
  end

  defp run_chat(model, state) do
    # Build system prompt with task context
    system_prompt = """
    #{@task_system_prompt}

    ## Current Task

    **Description**: #{state.description}
    """

    prompt =
      Prompt.new(%{
        messages: [
          %{role: :system, content: system_prompt, engine: :none},
          %{role: :user, content: state.prompt, engine: :none}
        ]
      })

    case ChatCompletion.run(
           %{
             model: model,
             prompt: prompt,
             stream: false
           },
           %{}
         ) do
      {:ok, %{content: content}} when is_binary(content) ->
        {:ok, content}

      {:ok, %{response: response}} when is_binary(response) ->
        {:ok, response}

      {:ok, result} when is_map(result) ->
        content = Map.get(result, :content) || Map.get(result, :response) || inspect(result)
        {:ok, content}

      {:ok, content} when is_binary(content) ->
        # Direct string response (rare but possible)
        {:ok, content}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp broadcast_started(topic, task_id, session_id) do
    message = {:task_started, task_id}
    Phoenix.PubSub.broadcast(@pubsub, topic, message)
    Phoenix.PubSub.broadcast(@pubsub, "tui.events", message)
    # Broadcast to session-specific topic if session_id available
    if session_id, do: Phoenix.PubSub.broadcast(@pubsub, "tui.events.#{session_id}", message)
  end

  defp broadcast_completed(topic, task_id, result, session_id) do
    message = {:task_completed, task_id, result}
    Phoenix.PubSub.broadcast(@pubsub, topic, message)
    Phoenix.PubSub.broadcast(@pubsub, "tui.events", message)
    # Broadcast to session-specific topic if session_id available
    if session_id, do: Phoenix.PubSub.broadcast(@pubsub, "tui.events.#{session_id}", message)
  end

  defp broadcast_failed(topic, task_id, reason, session_id) do
    message = {:task_failed, task_id, reason}
    Phoenix.PubSub.broadcast(@pubsub, topic, message)
    Phoenix.PubSub.broadcast(@pubsub, "tui.events", message)
    # Broadcast to session-specific topic if session_id available
    if session_id, do: Phoenix.PubSub.broadcast(@pubsub, "tui.events.#{session_id}", message)
  end
end
