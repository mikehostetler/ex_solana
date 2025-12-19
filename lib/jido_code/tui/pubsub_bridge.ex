defmodule JidoCode.TUI.PubSubBridge do
  @moduledoc """
  Bridges Phoenix PubSub messages to the TermUI Runtime.

  TermUI's Elm architecture only handles terminal events natively.
  This bridge subscribes to PubSub and forwards messages to the TUI
  component via TermUI.Runtime.send_message/3.

  ## Message Types Forwarded

  - `{:agent_response, content}` - Agent completed a response
  - `{:agent_status, status}` - Agent status changed
  - `{:reasoning_step, step}` - Reasoning step update
  - `{:config_changed, config}` - Configuration changed

  ## Usage

      # Started automatically by JidoCode.TUI.run/0
      {:ok, _pid} = PubSubBridge.start_link(runtime: JidoCode.TUI.Runtime)
  """

  use GenServer

  require Logger

  @pubsub_topic "tui.events"

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the PubSub bridge.

  ## Options

  - `:runtime` - The TUI Runtime name/pid to forward messages to (required)
  - `:name` - GenServer name (optional)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Stops the PubSub bridge.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(bridge) do
    GenServer.stop(bridge)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    runtime = Keyword.fetch!(opts, :runtime)

    # Subscribe to TUI events
    Phoenix.PubSub.subscribe(JidoCode.PubSub, @pubsub_topic)

    {:ok, %{runtime: runtime}}
  end

  @impl true
  def handle_info({:agent_response, _content} = msg, state) do
    forward_to_runtime(msg, state)
    {:noreply, state}
  end

  def handle_info({:agent_status, _status} = msg, state) do
    forward_to_runtime(msg, state)
    {:noreply, state}
  end

  def handle_info({:reasoning_step, _step} = msg, state) do
    forward_to_runtime(msg, state)
    {:noreply, state}
  end

  def handle_info({:config_changed, _config} = msg, state) do
    forward_to_runtime(msg, state)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("PubSubBridge ignoring unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp forward_to_runtime(msg, state) do
    # Send message to the root component (:root is the default ID for root component)
    TermUI.Runtime.send_message(state.runtime, :root, msg)
  end
end
