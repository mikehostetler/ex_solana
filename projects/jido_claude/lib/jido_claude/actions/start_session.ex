defmodule JidoClaude.Actions.StartSession do
  @moduledoc """
  Start a Claude Code session.

  This action initializes a Claude session by:
  1. Building SDK options from parameters
  2. Spawning a StreamRunner Task to handle the SDK stream
  3. Updating agent state to `:running`

  The StreamRunner runs in a fire-and-forget Task and dispatches messages
  back to the agent as `claude.internal.message` signals.

  ## Parameters

    * `prompt` - Required. The prompt to send to Claude.
    * `model` - Optional. Model to use ("haiku", "sonnet", "opus"). Default: "sonnet"
    * `max_turns` - Optional. Maximum agentic loop iterations. Default: 25
    * `allowed_tools` - Optional. List of allowed tool names. Default: ["Read", "Glob", "Grep", "Bash"]
    * `cwd` - Optional. Working directory for tools. Default: current directory
    * `system_prompt` - Optional. Custom system prompt.
    * `sdk_timeout_ms` - Optional. SDK-level timeout. Default: 600_000 (10 minutes)

  ## Example

      cmd(agent, {StartSession, %{
        prompt: "Analyze this codebase",
        model: "sonnet",
        max_turns: 50
      }})

  """

  use Jido.Action,
    name: "claude_start_session",
    description: "Start a Claude Code session",
    schema: [
      prompt: [type: :string, required: true],
      model: [type: :string, default: "sonnet"],
      max_turns: [type: :integer, default: 25],
      allowed_tools: [type: {:list, :string}, default: ["Read", "Glob", "Grep", "Bash"]],
      cwd: [type: :string, default: nil],
      system_prompt: [type: :string, default: nil],
      sdk_timeout_ms: [type: :integer, default: 600_000]
    ]

  alias Jido.Agent.Directive
  alias JidoClaude.StreamRunner

  @impl true
  def run(params, context) do
    agent_pid = context[:agent_pid] || self()
    session_id = get_session_id(context)

    options = build_options(params)

    result = %{
      status: :running,
      session_id: session_id,
      prompt: params.prompt,
      options: options,
      turns: 0,
      transcript: []
    }

    runner_spec =
      {Task,
       fn ->
         StreamRunner.run(%{
           agent_pid: agent_pid,
           prompt: params.prompt,
           options: options
         })
       end}

    directives = [
      Directive.spawn(runner_spec, :stream_runner)
    ]

    {:ok, result, directives}
  end

  defp get_session_id(context) do
    cond do
      context[:session_id] -> context.session_id
      context[:agent] && context.agent.state[:session_id] -> context.agent.state.session_id
      true -> generate_session_id()
    end
  end

  defp generate_session_id do
    "claude-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end

  defp build_options(params) do
    %{
      model: params.model,
      max_turns: params.max_turns,
      allowed_tools: params.allowed_tools,
      cwd: params[:cwd] || File.cwd!(),
      system_prompt: params[:system_prompt],
      timeout_ms: params[:sdk_timeout_ms]
    }
  end
end
