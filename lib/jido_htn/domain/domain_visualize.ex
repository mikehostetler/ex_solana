defmodule Jido.HTN.Visualize do
  @moduledoc """
  Provides advanced visualization capabilities for Jido.HTN.Domain structures.
  """

  alias Jido.HTN.CompoundTask
  alias Jido.HTN.Domain
  alias Jido.HTN.PrimitiveTask

  @doc """
  Generates a detailed Mermaid diagram string from a Jido.HTN.Domain struct.

  ## Parameters

  - domain: A Jido.HTN.Domain struct

  ## Returns

  A string containing the Mermaid diagram code.
  """
  @spec generate_mermaid(Domain.t()) :: String.t()
  def generate_mermaid(%Domain{} = domain) do
    tasks = domain.tasks

    diagram =
      [
        "graph TD",
        generate_nodes(tasks),
        generate_edges(domain),
        generate_task_details(domain),
        generate_subgraphs(tasks),
        generate_legend(),
        generate_styles(tasks)
      ]
      |> List.flatten()
      |> Enum.join("\n")

    diagram
  end

  defp generate_nodes(tasks) do
    Enum.map(tasks, fn {name, task} ->
      case task do
        %CompoundTask{} -> "    #{node_id(name)}{{\"#{name}\"}}"
        %PrimitiveTask{} -> "    #{node_id(name)}[\"#{name}\"]"
      end
    end)
  end

  defp generate_edges(%Domain{} = domain) do
    Enum.flat_map(domain.tasks, fn {name, task} ->
      case task do
        %CompoundTask{methods: methods} -> generate_method_edges(name, methods, domain)
        _ -> []
      end
    end)
  end

  defp generate_method_edges(task_name, methods, domain) do
    Enum.flat_map(methods, fn method ->
      subtasks = Map.get(method, :subtasks) || []
      conditions = Map.get(method, :conditions) || []
      condition_string = extract_conditions(conditions, domain)

      Enum.map(subtasks, fn subtask ->
        "    #{node_id(task_name)} -->|\"#{condition_string}\"| #{node_id(subtask)}"
      end)
    end)
  end

  defp generate_task_details(%Domain{} = domain) do
    Enum.flat_map(domain.tasks, fn {name, task} ->
      case task do
        %PrimitiveTask{} = pt ->
          [
            "    subgraph \"#{name} Details\"",
            "        #{node_id(name)}_pre[\"Preconditions:<br/>#{extract_conditions(pt.preconditions, domain)}\"]",
            "        #{node_id(name)}_eff[\"Effects:<br/>#{extract_effects(pt.effects, domain)}\"]",
            "        #{node_id(name)} --> #{node_id(name)}_pre",
            "        #{node_id(name)} --> #{node_id(name)}_eff",
            "    end"
          ]

        _ ->
          []
      end
    end)
  end

  defp generate_subgraphs(tasks) do
    compound_tasks =
      Enum.filter(tasks, fn {_, task} -> match?(%CompoundTask{}, task) end)

    primitive_tasks =
      Enum.filter(tasks, fn {_, task} -> match?(%PrimitiveTask{}, task) end)

    [
      "    subgraph Compound Tasks",
      Enum.map(compound_tasks, fn {name, _} -> "        #{node_id(name)}" end),
      "    end",
      "",
      "    subgraph Primitive Tasks",
      Enum.map(primitive_tasks, fn {name, _} -> "        #{node_id(name)}" end),
      "    end"
    ]
  end

  defp generate_legend do
    [
      "    subgraph Legend",
      "        compound_legend{{\"Compound Task\"}}",
      "        primitive_legend[\"Primitive Task\"]",
      "        condition_legend[\"Condition/Precondition/Effect\"]",
      "        anon_legend[\"[anon_cond] = Anonymous Function\"]",
      "    end",
      "    class compound_legend compound;",
      "    class primitive_legend primitive;",
      "    class condition_legend details;",
      "    class anon_legend details;"
    ]
  end

  defp generate_styles(tasks) do
    """
    classDef compound fill:#f9f,stroke:#333,stroke-width:2px;
    classDef primitive fill:#bbf,stroke:#333,stroke-width:2px;
    classDef details fill:#dfd,stroke:#333,stroke-width:1px;

    class #{get_compound_task_ids(tasks)} compound;
    class #{get_primitive_task_ids(tasks)} primitive;
    class #{get_detail_ids(tasks)} details;
    """
  end

  defp node_id(name) do
    "node_" <> String.replace(name, ~r/[^a-zA-Z0-9]/, "_")
  end

  defp extract_conditions(conditions, domain) do
    conditions
    |> Enum.map(&extract_function_name(&1, domain))
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp extract_effects(effects, domain) do
    effects
    |> Enum.map(&extract_function_name(&1, domain))
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp extract_function_name(name, _domain) when is_binary(name), do: name

  defp extract_function_name(func, domain) when is_function(func) do
    info = Function.info(func)
    module = Keyword.get(info, :module)
    name = Keyword.get(info, :name)
    arity = Keyword.get(info, :arity)

    if module != :erl_eval and name do
      "#{inspect(module)}.#{name}/#{arity}"
    else
      find_callback_name(func, domain.callbacks) || "[anon_cond]"
    end
  end

  defp extract_function_name(_, _domain), do: nil

  defp find_callback_name(func, callbacks) do
    Enum.find_value(callbacks, fn {name, callback} ->
      if callback == func, do: name, else: nil
    end)
  end

  defp get_compound_task_ids(tasks) do
    tasks
    |> Enum.filter(fn {_, task} -> match?(%CompoundTask{}, task) end)
    |> Enum.map_join(",", fn {name, _} -> node_id(name) end)
  end

  defp get_primitive_task_ids(tasks) do
    tasks
    |> Enum.filter(fn {_, task} -> match?(%PrimitiveTask{}, task) end)
    |> Enum.map_join(",", fn {name, _} -> node_id(name) end)
  end

  defp get_detail_ids(tasks) do
    tasks
    |> Enum.filter(fn {_, task} -> match?(%PrimitiveTask{}, task) end)
    |> Enum.flat_map(fn {name, _} -> ["#{node_id(name)}_pre", "#{node_id(name)}_eff"] end)
    |> Enum.join(",")
  end
end
