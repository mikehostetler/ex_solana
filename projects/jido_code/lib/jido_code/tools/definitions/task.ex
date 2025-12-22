defmodule JidoCode.Tools.Definitions.Task do
  @moduledoc """
  Tool definitions for multi-agent task operations.

  This module defines the spawn_task tool for delegating complex sub-tasks
  to specialized agents with their own LLM context.

  ## Available Tools

  - `spawn_task` - Spawn a sub-agent to execute a complex task

  ## Usage

      # Register task tools
      for tool <- Task.all() do
        :ok = Registry.register(tool)
      end

  ## Sub-Agent Types

  The `subagent_type` parameter is a hint for future agent specialization:

  - `"general"` - General purpose task execution (default)
  - `"explore"` - Codebase exploration and search
  - `"research"` - Web research and documentation lookup
  - `"test"` - Test writing and execution

  Currently all sub-agents use the same general TaskAgent implementation.
  """

  alias JidoCode.Tools.Handlers.Task, as: Handler
  alias JidoCode.Tools.Tool

  @doc """
  Returns all task tools.

  ## Returns

  List of `%Tool{}` structs ready for registration.
  """
  @spec all() :: [Tool.t()]
  def all do
    [
      spawn_task()
    ]
  end

  @doc """
  Returns the spawn_task tool definition.

  Spawns a specialized sub-agent to handle complex tasks that benefit
  from isolated LLM context and focused execution.

  ## Parameters

  - `description` (required, string) - Short task description (max 200 chars)
  - `prompt` (required, string) - Detailed task instructions (max 10000 chars)
  - `subagent_type` (optional, string) - Agent specialization hint
  - `model` (optional, string) - Override model for sub-agent
  - `timeout` (optional, integer) - Task timeout in ms (default 60000, max 300000)

  ## Use Cases

  - Codebase exploration requiring multiple search operations
  - Research tasks that need web lookups
  - Multi-step refactoring with checkpoint results
  - Parallel execution of independent sub-tasks
  """
  @spec spawn_task() :: Tool.t()
  def spawn_task do
    Tool.new!(%{
      name: "spawn_task",
      description:
        "Spawn a sub-agent to execute a complex task autonomously. " <>
          "Use for tasks requiring focused attention, multiple operations, " <>
          "or isolated context. The sub-agent will execute the task and return results. " <>
          "Good for: codebase exploration, research, multi-step operations.",
      handler: Handler,
      parameters: [
        %{
          name: "description",
          type: :string,
          description: "Short task description (1-3 words, max 200 chars)",
          required: true
        },
        %{
          name: "prompt",
          type: :string,
          description:
            "Detailed task instructions. Be specific about what to find, " <>
              "analyze, or produce. Include context the sub-agent needs.",
          required: true
        },
        %{
          name: "subagent_type",
          type: :string,
          description:
            "Agent specialization hint: 'general' (default), 'explore', 'research', 'test'",
          required: false
        },
        %{
          name: "model",
          type: :string,
          description: "Override model for sub-agent (e.g., 'claude-3-5-sonnet-20241022')",
          required: false
        },
        %{
          name: "timeout",
          type: :integer,
          description: "Task timeout in milliseconds (default 60000, max 300000)",
          required: false
        }
      ]
    })
  end
end
