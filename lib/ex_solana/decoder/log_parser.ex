defmodule ExSolana.Decoder.LogParser do
  @moduledoc false
  use ExSolana.Util.DebugTools, debug_enabled: false
  use TypedStruct

  @max_depth 10

  typedstruct module: Node do
    field(:id, integer())
    field(:top_level_id, integer())
    field(:program, String.t())
    field(:level, integer())
    field(:children, list())
    field(:parent, integer() | nil)
    field(:logs, list())
  end

  @spec parse_logs([String.t()]) :: list()
  def parse_logs(logs) do
    debug("Starting parse_logs with #{length(logs)} logs")

    {invocations, _, _} =
      Enum.reduce(logs, {[], [], 0}, &process_log/2)

    debug("Finished processing logs, invocations count: #{length(invocations)}")

    result =
      invocations
      |> Enum.reverse()
      |> build_tree()

    debug("Finished building tree, root nodes count: #{length(result)}")
    {:ok, result}
  end

  defp process_log(log, {invocations, stack, top_level_id}) do
    debug("Processing log: #{log}")

    cond do
      String.starts_with?(log, "Program ") and String.contains?(log, "invoke") ->
        debug("Invoking program")
        process_invoke(log, invocations, stack, top_level_id)

      String.starts_with?(log, "Program ") and String.contains?(log, "success") ->
        debug("Program success")
        process_success(invocations, stack, top_level_id)

      true ->
        debug("Intermediate log")
        process_intermediate(log, invocations, stack, top_level_id)
    end
  end

  defp process_invoke(log, invocations, stack, top_level_id) do
    debug("Processing invoke: #{log}")
    [program, level] = extract_invoke_info(log)
    new_id = length(invocations) + 1

    if length(stack) >= @max_depth do
      error("Maximum depth reached. Skipping further nesting.")
      {invocations, stack, top_level_id}
    else
      parent = List.first(stack)

      {new_top_level_id, node_top_level_id} =
        if level == 1 do
          {top_level_id + 1, top_level_id + 1}
        else
          {top_level_id, 0}
        end

      new_node = %Node{
        id: new_id,
        top_level_id: node_top_level_id,
        program: program,
        level: level,
        children: [],
        parent: parent,
        logs: [log]
      }

      debug(
        "Created new node: id=#{new_id}, top_level_id=#{node_top_level_id}, program=#{program}, level=#{level}, parent=#{inspect(parent)}"
      )

      {[new_node | invocations], [new_id | stack], new_top_level_id}
    end
  end

  defp process_success(invocations, [current | rest_stack], top_level_id) do
    debug("Processing success, popping stack")

    updated_invocations =
      add_log_to_current(
        invocations,
        current,
        "Program #{get_program(invocations, current)} success"
      )

    {updated_invocations, rest_stack, top_level_id}
  end

  defp process_success(invocations, [], top_level_id) do
    debug("Processing success with empty stack")
    {invocations, [], top_level_id}
  end

  defp process_intermediate(log, invocations, [current | _] = stack, top_level_id) do
    debug("Processing intermediate log for node #{inspect(current)}")
    updated_invocations = add_log_to_current(invocations, current, log)
    {updated_invocations, stack, top_level_id}
  end

  defp process_intermediate(log, invocations, [], top_level_id) do
    debug("Processing intermediate log with empty stack")
    new_id = length(invocations) + 1

    new_node = %Node{
      id: new_id,
      top_level_id: top_level_id + 1,
      program: "Unknown",
      level: 1,
      children: [],
      parent: nil,
      logs: [log]
    }

    {[new_node | invocations], [], top_level_id + 1}
  end

  defp add_log_to_current(invocations, current_id, log) do
    Enum.map(invocations, fn
      %{id: ^current_id} = node ->
        %{node | logs: [log | node.logs]}

      other ->
        other
    end)
  end

  defp get_program(invocations, id) do
    Enum.find_value(invocations, fn
      %{id: ^id, program: program} -> program
      _ -> nil
    end)
  end

  defp extract_invoke_info(log) do
    debug("Extracting invoke info from: #{log}")

    case Regex.run(~r/Program (.*) invoke \[(\d+)\]/, log, capture: :all_but_first) do
      [program, level] ->
        debug("Extracted program: #{program}, level: #{level}")
        [program, String.to_integer(level)]

      _ ->
        debug("Failed to extract invoke info")
        ["Unknown", 0]
    end
  end

  def build_tree(invocations) do
    debug("Starting to build tree with #{length(invocations)} invocations")

    {tree, _} =
      Enum.reduce(invocations, {%{}, %{}}, fn node, {tree, parent_map} ->
        node =
          Map.update!(
            node,
            :logs,
            &Enum.reject(&1, fn log ->
              String.ends_with?(log, "invoke [#{node.level}]") or
                String.ends_with?(log, "success")
            end)
          )

        updated_tree = Map.put(tree, node.id, node)
        updated_parent_map = Map.put(parent_map, node.id, node.parent)

        case node.parent do
          nil ->
            {updated_tree, updated_parent_map}

          parent_id ->
            parent_node = Map.get(updated_tree, parent_id)

            updated_parent_node = %{
              parent_node
              | children: [node.id | parent_node.children || []]
            }

            updated_tree = Map.put(updated_tree, parent_id, updated_parent_node)

            {updated_tree, updated_parent_map}
        end
      end)

    result =
      tree
      |> Map.values()
      |> Enum.filter(&is_nil(&1.parent))
      |> Enum.map(&expand_children(&1, tree))
      |> Enum.map(&sort_children_recursive/1)

    debug("Finished building tree, root nodes: #{length(result)}")
    result
  end

  defp expand_children(node, tree) do
    children = Enum.map(node.children || [], &expand_children(tree[&1], tree))
    %{node | children: children}
  end

  defp sort_children_recursive(node) do
    sorted_children =
      node.children
      |> Enum.map(&sort_children_recursive/1)
      |> Enum.sort_by(& &1.id)

    %{node | children: sorted_children}
  end

  @spec print_tree(list()) :: :ok
  def print_tree(tree) do
    debug("Printing tree with #{length(tree)} root nodes")
    Enum.each(tree, &print_node(&1, 0))
  end

  defp print_node(node, indent) do
    debug("Printing node #{node.id} at indent level #{indent}")

    IO.puts(
      "#{String.duplicate("  ", indent)}#{node.program} (level #{node.level}, id #{node.id}, top_level_id #{node.top_level_id})"
    )

    IO.puts("#{String.duplicate("  ", indent)}Logs:")
    Enum.each(node.logs, &IO.puts("#{String.duplicate("  ", indent + 1)}#{&1}"))
    Enum.each(node.children, &print_node(&1, indent + 1))
  end
end
