defmodule JidoClaude.Parent.SpawnSession do
  @moduledoc """
  Spawn a ClaudeSessionAgent as a child of the parent agent.

  This action is used by orchestrator/parent agents to spawn child
  Claude sessions. Each session runs independently and emits signals
  back to the parent for status updates.

  ## Parameters

    * `prompt` - Required. The prompt to send to Claude.
    * `session_id` - Optional. Unique session identifier. Auto-generated if nil.
    * `model` - Optional. Model to use ("haiku", "sonnet", "opus"). Default: "sonnet"
    * `max_turns` - Optional. Maximum agentic loop iterations. Default: 25
    * `allowed_tools` - Optional. List of allowed tool names. Default: ["Read", "Glob", "Grep", "Bash"]
    * `cwd` - Optional. Working directory for tools. Default: current directory
    * `system_prompt` - Optional. Custom system prompt.
    * `meta` - Optional. Custom metadata to track with this session.

  ## Example

      # Spawn with explicit session_id
      {agent, _} = cmd(agent, {SpawnSession, %{
        session_id: "review-pr-123",
        prompt: "Review PR #123 for security issues"
      }})

      # Spawn with auto-generated session_id
      {agent, _} = cmd(agent, {SpawnSession, %{
        prompt: "Analyze dependencies"
      }})

  """

  use Jido.Action,
    name: "claude_spawn_session",
    description: "Spawn a ClaudeSessionAgent as a child",
    schema: [
      prompt: [type: :string, required: true],
      session_id: [type: :string, default: nil],
      model: [type: :string, default: "sonnet"],
      max_turns: [type: :integer, default: 25],
      allowed_tools: [type: {:list, :string}, default: ["Read", "Glob", "Grep", "Bash"]],
      cwd: [type: :string, default: nil],
      system_prompt: [type: :string, default: nil],
      meta: [type: :map, default: %{}]
    ]

  alias Jido.Agent.Directive
  alias JidoClaude.ClaudeSessionAgent
  alias JidoClaude.Parent.SessionRegistry

  @impl true
  def run(params, context) do
    session_id = params[:session_id] || generate_session_id()
    agent = context[:agent]

    initial_state = %{
      session_id: session_id,
      prompt: params.prompt,
      options: %{
        model: params.model,
        max_turns: params.max_turns,
        allowed_tools: params.allowed_tools,
        cwd: params[:cwd],
        system_prompt: params[:system_prompt]
      }
    }

    current_state = if agent, do: agent.state, else: %{}

    state_update =
      current_state
      |> SessionRegistry.init_sessions()
      |> SessionRegistry.register_session(session_id, %{
        prompt: params.prompt,
        model: params.model,
        meta: params[:meta] || %{}
      })
      |> Map.take([:sessions])

    directive =
      Directive.spawn_agent(
        ClaudeSessionAgent,
        session_id,
        opts: %{initial_state: initial_state},
        meta: %{session_id: session_id}
      )

    {:ok, state_update, [directive]}
  end

  defp generate_session_id do
    "claude-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end
end
