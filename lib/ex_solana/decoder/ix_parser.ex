defmodule ExSolana.Decoder.IxParser do
  @moduledoc false
  alias ExSolana.Decoder.LogParser.Node

  require Logger

  defstruct [:ix, :logs, :program, :children]

  @type t :: %__MODULE__{
          ix: map() | nil,
          logs: [String.t()],
          program: String.t(),
          children: [t()]
        }

  @type instruction :: map()
  @type parsed_node :: Node.t()

  # @spec parse(ConfirmedTransaction.t(), [parsed_node()]) :: [t()]
  def parse(transaction, parsed_logs) do
    instructions = transaction.transaction.transaction.message.instructions
    inner_instructions = transaction.transaction.meta.inner_instructions || []
    inner_instruction_map = create_inner_instruction_map(inner_instructions)

    {:ok, merge_instructions(parsed_logs, instructions, inner_instruction_map)}
  end

  # @spec merge_instructions([parsed_node()], [instruction()], map()) :: [t()]
  defp merge_instructions(parsed_nodes, instructions, inner_instruction_map) do
    parsed_nodes
    |> Enum.with_index(1)
    |> Enum.map(fn {node, index} ->
      case Enum.at(instructions, index - 1) do
        nil ->
          Logger.warning("No matching instruction found for node #{index}")
          node_to_parsed_ix(node)

        instruction ->
          inner_instructions = Map.get(inner_instruction_map, index, [])
          merge_instruction(node, instruction, inner_instructions)
      end
    end)
  end

  # @spec merge_instruction(parsed_node(), instruction(), [instruction()]) :: t()
  defp merge_instruction(%Node{children: []} = node, instruction, _inner_instructions) do
    %__MODULE__{
      ix: instruction,
      logs: node.logs,
      program: node.program,
      children: []
    }
  end

  defp merge_instruction(%Node{children: children, level: level} = node, instruction, inner_instructions)
       when length(children) > 0 and level <= 1 do
    merged_children = merge_children(children, inner_instructions)

    %__MODULE__{
      ix: instruction,
      logs: node.logs,
      program: node.program,
      children: merged_children
    }
  end

  defp merge_instruction(node, instruction, _inner_instructions) do
    %__MODULE__{
      ix: instruction,
      logs: node.logs,
      program: node.program,
      children: []
    }
  end

  @spec merge_children([parsed_node()], [instruction()]) :: [t()]
  defp merge_children(children, inner_instructions) do
    children
    |> Enum.with_index()
    |> Enum.map(fn {child, index} ->
      case Enum.at(inner_instructions, index) do
        nil ->
          Logger.warning("No matching inner instruction found for child node #{index}")
          node_to_parsed_ix(child)

        inner_instruction ->
          merge_instruction(child, inner_instruction, [])
      end
    end)
  end

  @spec create_inner_instruction_map([map()] | [{integer(), [map()]}]) :: map()
  defp create_inner_instruction_map(inner_instructions) do
    inner_instructions
    |> Enum.map(fn
      {index, instructions} when is_integer(index) ->
        {index + 1, instructions}

      %{index: index, instructions: instructions} ->
        {index + 1, instructions}

      other ->
        Logger.warning("Unexpected inner instruction format: #{inspect(other)}")
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  @spec node_to_parsed_ix(parsed_node()) :: t()
  defp node_to_parsed_ix(%Node{} = node) do
    %__MODULE__{
      ix: nil,
      logs: node.logs,
      program: node.program,
      children: Enum.map(node.children, &node_to_parsed_ix/1)
    }
  end

  # defp merge_instructions(parsed_logs, instructions, inner_instructions) do
  #   instruction_list = Enum.with_index(instructions)
  #   inner_instruction_map = create_inner_instruction_map(inner_instructions)

  #   parsed_logs
  #   |> Enum.reduce({[], instruction_list}, &process_log(&1, &2, inner_instruction_map))
  #   |> elem(0)
  #   |> Enum.reverse()
  # end

  # defp create_inner_instruction_map(inner_instructions) do
  #   inner_instructions
  #   |> Enum.map(fn
  #     {index, instructions} when is_integer(index) ->
  #       {index + 1, instructions}

  #     %{index: index, instructions: instructions} ->
  #       {index + 1, instructions}

  #     other ->
  #       Logger.warning("Unexpected inner instruction format: #{inspect(other)}")
  #       nil
  #   end)
  #   |> Enum.reject(&is_nil/1)
  #   |> Map.new()
  # end

  # defp process_log(log, {acc, remaining_instructions}, inner_instruction_map) do
  #   case find_matching_instruction(remaining_instructions, log.program) do
  #     {instruction, updated_instructions} ->
  #       inner_instr =
  #         if log.level == 1 do
  #           Map.get(inner_instruction_map, log.top_level_id)
  #         end

  #       parsed_instruction = create_parsed_instruction(log, instruction, inner_instr, [])

  #       # Process all children
  #       parsed_instruction =
  #         if log.children && log.level == 1 do
  #           children =
  #             Enum.map(log.children, fn child ->
  #               child_inner_instr = Map.get(inner_instruction_map, child.id)
  #               create_parsed_instruction(child, nil, child_inner_instr, [])
  #             end)

  #           %{parsed_instruction | children: children}
  #         else
  #           parsed_instruction
  #         end

  #       {[parsed_instruction | acc], updated_instructions}

  #     nil ->
  #       Logger.warning("No matching instruction found for log", log: log)
  #       {acc, remaining_instructions}
  #   end
  # end

  # defp find_matching_instruction([], _program), do: nil

  # defp find_matching_instruction([{instruction, _index} | tail], program) when is_map(instruction) do
  #   if instruction.program == program do
  #     {instruction, tail}
  #   else
  #     find_matching_instruction(tail, program)
  #   end
  # end

  # defp find_matching_instruction([{instruction, index} | tail], program) when is_tuple(instruction) do
  #   if elem(instruction, 0).program == program do
  #     {elem(instruction, 0), tail}
  #   else
  #     find_matching_instruction(tail, program)
  #   end
  # end

  # defp process_children(log, instructions, inner_instruction_map) do
  #   merge_instructions(log.children || [], instructions, inner_instruction_map)
  # end

  # defp create_parsed_instruction(log, instruction, inner_instr, children) do
  #   base_instruction = %Core.ParsedIx{
  #     id: log.id,
  #     parent: log.parent,
  #     level: log.level,
  #     children: children,
  #     logs: log.logs,
  #     program: log.program,
  #     ix: instruction || (inner_instr && List.first(inner_instr))
  #   }

  #   maybe_add_inner_instructions(base_instruction, inner_instr)
  # end

  # defp maybe_add_inner_instructions(parsed_instruction, nil), do: parsed_instruction

  # defp maybe_add_inner_instructions(parsed_instruction, inner_instructions) do
  #   additional_children =
  #     Enum.map(inner_instructions, fn instr ->
  #       %Core.ParsedIx{
  #         id: nil,
  #         parent: parsed_instruction.id,
  #         level: parsed_instruction.level + 1,
  #         children: [],
  #         logs: [],
  #         program: instr.program,
  #         ix: instr
  #       }
  #     end)

  #   %{parsed_instruction | children: parsed_instruction.children ++ additional_children}
  # end
end
