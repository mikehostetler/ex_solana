defmodule JidoCode.Tools.Definitions.Todo do
  @moduledoc """
  Tool definitions for task tracking operations.

  This module defines the todo_write tool for managing structured task lists
  that can be registered with the Registry and used by the LLM agent.

  ## Available Tools

  - `todo_write` - Write/update the task tracking list

  ## Usage

      # Register todo tools
      for tool <- Todo.all() do
        :ok = Registry.register(tool)
      end
  """

  alias JidoCode.Tools.Handlers.Todo, as: Handler
  alias JidoCode.Tools.Tool

  @doc """
  Returns all todo tools.

  ## Returns

  List of `%Tool{}` structs ready for registration.
  """
  @spec all() :: [Tool.t()]
  def all do
    [
      todo_write()
    ]
  end

  @doc """
  Returns the todo_write tool definition.

  Manages a structured task list for tracking work progress.

  ## Parameters

  - `todos` (required, array) - Array of todo objects, each with:
    - `content` (required, string) - Task description
    - `status` (required, string) - "pending", "in_progress", or "completed"
    - `active_form` (required, string) - Present tense description
  """
  @spec todo_write() :: Tool.t()
  def todo_write do
    Tool.new!(%{
      name: "todo_write",
      description:
        "Write or update the task tracking list. " <>
          "Use this tool to plan multi-step tasks and track progress. " <>
          "Each todo has content (what to do), status (pending/in_progress/completed), " <>
          "and active_form (present tense description shown during execution).",
      handler: Handler,
      parameters: [
        %{
          name: "todos",
          type: :array,
          description:
            "Array of todo objects. Each object must have: " <>
              "'content' (task description), " <>
              "'status' (pending/in_progress/completed), " <>
              "'active_form' (present tense description)",
          required: true
        }
      ]
    })
  end
end
