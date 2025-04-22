defmodule ExSolana.Decoder.TxnActions do
  @moduledoc false
  require Logger

  defmodule ActionNode do
    @moduledoc false
    defstruct [:action, :children, :program, :logs]

    @type t :: %__MODULE__{
            action: struct() | {:unknown_action, map()},
            children: [t()],
            program: String.t(),
            logs: [String.t()]
          }
  end

  def extract(parsed_txn) do
    action_tree = extract_actions_recursively(parsed_txn)
    human_readable = generate_human_readable(action_tree)

    {:ok, %{actions: action_tree, human_readable: human_readable}}
  rescue
    e ->
      Logger.warning("Error extracting actions: #{inspect(e)}", stacktrace: __STACKTRACE__)
      {:error, :action_extraction_failed, e}
  end

  defp extract_actions_recursively(parsed_txn) when is_list(parsed_txn) do
    Enum.map(parsed_txn, &extract_actions_recursively/1)
  end

  defp extract_actions_recursively(%{action: action, children: children, program: program, logs: logs}) do
    %ActionNode{
      action: action,
      children: extract_actions_recursively(children),
      program: program,
      logs: logs
    }
  end

  defp extract_actions_recursively(%{action: action, program: program, logs: logs}) do
    %ActionNode{
      action: action,
      children: [],
      program: program,
      logs: logs
    }
  end

  defp extract_actions_recursively(other) do
    Logger.warning("Unexpected structure in extract_actions_recursively: #{inspect(other)}")
    %ActionNode{action: {:unknown_action, %{}}, children: [], program: "unknown", logs: []}
  end

  defp generate_human_readable(action_tree, depth \\ 0) do
    action_tree
    |> List.wrap()
    |> Enum.map(fn %ActionNode{action: action, children: children, program: program} ->
      action_str = to_human_readable(action)
      indentation = String.duplicate("  ", depth)
      program_str = if program, do: " (Program: #{program})", else: ""

      [
        "#{indentation}#{action_str}#{program_str}"
        | generate_human_readable(children, depth + 1)
      ]
    end)
    |> List.flatten()
  end

  defp to_human_readable(%{__struct__: module} = action) do
    if function_exported?(module, :to_human_readable, 1) do
      module.to_human_readable(action)
    else
      "Unknown action: #{inspect(action)}"
    end
  end

  defp to_human_readable({:unknown_action, details}) do
    "Unknown action: #{inspect(details)}"
  end

  defp to_human_readable(action) do
    "Unhandled action: #{inspect(action)}"
  end
end
