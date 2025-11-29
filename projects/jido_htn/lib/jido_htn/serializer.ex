defmodule Jido.HTN.Domain.Serializer do
  @moduledoc false

  alias Jido.HTN.CompoundTask
  alias Jido.HTN.Domain
  alias Jido.HTN.Method
  alias Jido.HTN.PrimitiveTask

  @spec serialize(Domain.t()) :: String.t()
  def serialize(domain) do
    Jason.encode!(domain, pretty: true)
  end

  @spec deserialize(String.t()) :: {:ok, Domain.t()} | {:error, String.t()}
  def deserialize(json) do
    with {:ok, data} <- Jason.decode(json),
         {:ok, domain} <- deserialize_domain(data) do
      {:ok, domain}
    else
      {:error, reason} -> {:error, "Failed to deserialize domain: #{inspect(reason)}"}
    end
  end

  defp deserialize_domain(data) do
    with {:ok, tasks} <- deserialize_tasks(data["tasks"]),
         {:ok, allowed_workflows} <- deserialize_allowed_workflows(data["allowed_workflows"]),
         {:ok, callbacks} <- deserialize_callbacks(data["callbacks"]) do
      {:ok,
       %Domain{
         name: data["name"],
         tasks: tasks,
         allowed_workflows: allowed_workflows,
         callbacks: callbacks,
         root_tasks: MapSet.new(data["root_tasks"])
       }}
    end
  end

  defp deserialize_tasks(tasks) do
    Enum.reduce_while(tasks, {:ok, %{}}, fn {name, task}, {:ok, acc} ->
      case deserialize_task(task) do
        {:ok, deserialized_task} -> {:cont, {:ok, Map.put(acc, name, deserialized_task)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp deserialize_task(%{"type" => "compound", "name" => name, "methods" => methods}) do
    with {:ok, deserialized_methods} <- deserialize_methods(methods) do
      {:ok, %CompoundTask{name: name, methods: deserialized_methods}}
    end
  end

  defp deserialize_task(%{
         "type" => "primitive",
         "name" => name,
         "task" => %{"module" => module, "opts" => opts},
         "preconditions" => preconditions,
         "effects" => effects,
         "expected_effects" => expected_effects,
         "cost" => cost,
         "duration" => duration
       }) do
    with {:ok, deserialized_module} <- deserialize_module(module),
         {:ok, deserialized_preconditions} <- deserialize_functions(preconditions),
         {:ok, deserialized_effects} <- deserialize_functions(effects),
         {:ok, deserialized_expected_effects} <- deserialize_functions(expected_effects) do
      {:ok,
       %PrimitiveTask{
         name: name,
         task: {deserialized_module, opts},
         preconditions: deserialized_preconditions,
         effects: deserialized_effects,
         expected_effects: deserialized_expected_effects,
         cost: cost,
         duration: duration
       }}
    end
  end

  defp deserialize_task(%{
         "type" => "primitive",
         "name" => name,
         "task" => %{"module" => module, "opts" => opts},
         "preconditions" => preconditions,
         "effects" => effects,
         "expected_effects" => expected_effects
       }) do
    with {:ok, deserialized_module} <- deserialize_module(module),
         {:ok, deserialized_preconditions} <- deserialize_functions(preconditions),
         {:ok, deserialized_effects} <- deserialize_functions(effects),
         {:ok, deserialized_expected_effects} <- deserialize_functions(expected_effects) do
      {:ok,
       %PrimitiveTask{
         name: name,
         task: {deserialized_module, opts},
         preconditions: deserialized_preconditions,
         effects: deserialized_effects,
         expected_effects: deserialized_expected_effects
       }}
    end
  end

  defp deserialize_task(_), do: {:error, "Invalid task format"}

  defp deserialize_methods(methods) do
    result =
      Enum.reduce_while(methods, {:ok, []}, fn method, {:ok, acc} ->
        case deserialize_method(method) do
          {:ok, deserialized_method} -> {:cont, {:ok, [deserialized_method | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp deserialize_method(%{
         "name" => name,
         "priority" => priority,
         "conditions" => conditions,
         "subtasks" => subtasks,
         "ordering" => ordering
       }) do
    with {:ok, deserialized_conditions} <- deserialize_functions(conditions) do
      {:ok,
       %Method{
         name: name,
         priority: priority,
         conditions: deserialized_conditions,
         subtasks: subtasks,
         ordering:
           Enum.map(ordering, fn %{"before" => before, "after" => after_} -> {before, after_} end)
       }}
    end
  end

  defp deserialize_method(%{"conditions" => conditions, "subtasks" => subtasks}) do
    with {:ok, deserialized_conditions} <- deserialize_functions(conditions) do
      {:ok, %Method{conditions: deserialized_conditions, subtasks: subtasks}}
    end
  end

  defp deserialize_method(_), do: {:error, "Invalid method format"}

  defp deserialize_allowed_workflows(allowed_workflows) do
    Enum.reduce_while(allowed_workflows, {:ok, %{}}, fn {name, module}, {:ok, acc} ->
      case deserialize_module(module) do
        {:ok, deserialized_module} -> {:cont, {:ok, Map.put(acc, name, deserialized_module)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp deserialize_callbacks(callbacks) do
    Enum.reduce_while(callbacks, {:ok, %{}}, fn {name, callback}, {:ok, acc} ->
      case deserialize_function(callback) do
        {:ok, deserialized_callback} -> {:cont, {:ok, Map.put(acc, name, deserialized_callback)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp deserialize_functions(functions) do
    result =
      Enum.reduce_while(functions, {:ok, []}, fn func, {:ok, acc} ->
        case deserialize_function(func) do
          {:ok, deserialized_func} -> {:cont, {:ok, [deserialized_func | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp deserialize_module(module_name) when is_binary(module_name) do
    try do
      module = String.to_existing_atom(module_name)
      {:ok, module}
    rescue
      ArgumentError -> {:error, "Module #{module_name} does not exist"}
    end
  end

  defp deserialize_function(%{"__jido_mfa__" => %{"m" => mod, "f" => fun, "a" => arity}}) do
    try do
      module = String.to_existing_atom(to_string(mod))
      function_name = String.to_existing_atom(to_string(fun))

      if Code.ensure_loaded?(module) and function_exported?(module, function_name, arity) do
        {:ok, Function.capture(module, function_name, arity)}
      else
        {:error, "Cannot deserialize MFA: #{module}.#{function_name}/#{arity} not found"}
      end
    rescue
      ArgumentError -> {:error, "Cannot deserialize MFA: module or function does not exist"}
    end
  end

  defp deserialize_function(val) when is_boolean(val), do: {:ok, val}
  defp deserialize_function(val) when is_binary(val), do: {:ok, val}
  defp deserialize_function(func) when is_function(func), do: {:ok, func}
  defp deserialize_function(_), do: {:error, "Invalid function format"}
end

defimpl Jason.Encoder, for: Jido.HTN.Domain do
  alias Jido.HTN.CompoundTask
  alias Jido.HTN.Method
  alias Jido.HTN.PrimitiveTask

  def encode(domain, opts) do
    Jason.Encode.map(
      %{
        name: domain.name,
        tasks: encode_tasks(domain.tasks),
        allowed_workflows: encode_allowed_workflows(domain.allowed_workflows),
        callbacks: encode_callbacks(domain.callbacks),
        root_tasks: MapSet.to_list(domain.root_tasks)
      },
      opts
    )
  end

  defp encode_tasks(tasks) do
    Map.new(tasks, fn {name, task} -> {name, encode_task(task)} end)
  end

  defp encode_task(%CompoundTask{} = task) do
    %{
      type: "compound",
      name: task.name,
      methods: Enum.map(task.methods, &encode_method/1)
    }
  end

  defp encode_task(%PrimitiveTask{} = task) do
    encoded = %{
      type: "primitive",
      name: task.name,
      task: encode_workflow(task.task),
      preconditions: encode_functions(task.preconditions),
      effects: encode_functions(task.effects),
      expected_effects: encode_functions(task.expected_effects)
    }

    encoded = if task.cost, do: Map.put(encoded, :cost, task.cost), else: encoded
    encoded = if task.duration, do: Map.put(encoded, :duration, task.duration), else: encoded
    encoded
  end

  defp encode_method(%Method{} = method) do
    %{
      name: method.name,
      priority: method.priority,
      conditions: encode_functions(method.conditions),
      subtasks: method.subtasks,
      ordering:
        Enum.map(method.ordering || [], fn {before, after_} ->
          %{before: before, after: after_}
        end)
    }
  end

  defp encode_allowed_workflows(allowed_workflows) do
    Map.new(allowed_workflows, fn {name, module} -> {name, Atom.to_string(module)} end)
  end

  defp encode_callbacks(callbacks) do
    Map.new(callbacks, fn {name, callback} -> {name, serialize_function(callback)} end)
  end

  defp encode_workflow({module, opts}) do
    %{
      module: Atom.to_string(module),
      opts: opts
    }
  end

  defp encode_functions(functions) do
    Enum.map(functions, &serialize_function/1)
  end

  defp serialize_function(fun) when is_function(fun) do
    info = Function.info(fun)
    name = info[:name] |> Atom.to_string()

    # Check for anonymous functions - :erl_eval module or names starting with "-"
    if info[:module] == :erl_eval or String.starts_with?(name, "-") do
      raise "Anonymous functions cannot be reliably serialized. Use named functions or callback name strings."
    else
      %{
        __jido_mfa__: %{
          m: info[:module],
          f: info[:name],
          a: info[:arity]
        }
      }
    end
  end

  defp serialize_function(other), do: other
end
