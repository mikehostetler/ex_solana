defmodule Jido.HTN.Domain.Builder do
  @moduledoc false

  alias Jido.HTN.Domain

  @schema Zoi.struct(
            __MODULE__,
            %{
              domain:
                Zoi.any(description: "Domain being built")
                |> Zoi.optional(),
              error:
                Zoi.string(description: "Error message if build failed")
                |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @spec new(Domain.t()) :: {:ok, t()} | {:error, term()}
  def new(domain) do
    Zoi.parse(@schema, %{domain: domain})
  end

  def new!(domain) do
    case new(domain) do
      {:ok, builder} -> builder
      {:error, reason} -> raise ArgumentError, "Invalid Builder: #{inspect(reason)}"
    end
  end

  @spec error(String.t()) :: {:ok, t()} | {:error, term()}
  def error(msg) do
    Zoi.parse(@schema, %{error: msg})
  end

  def error!(msg) do
    case error(msg) do
      {:ok, builder} -> builder
      {:error, reason} -> raise ArgumentError, "Invalid Builder: #{inspect(reason)}"
    end
  end
end

defmodule Jido.HTN.Domain.BuilderHelpers do
  @moduledoc false
  require Logger

  alias Jido.HTN.CompoundTask
  alias Jido.HTN.Domain
  alias Jido.HTN.Domain.Builder
  alias Jido.HTN.Method
  alias Jido.HTN.PrimitiveTask

  @doc "Creates a new HTN domain with the given name."
  @spec new(String.t()) :: Builder.t()
  def new(name) when is_binary(name) do
    Logger.debug("Creating new domain", domain_name: name)
    case Zoi.parse(Domain.schema(), %{name: name}) do
      {:ok, domain} -> Builder.new!(domain)
      {:error, _reason} -> Builder.error!("Invalid domain: #{inspect(name)}")
    end
  end

  def new(name), do: Builder.error!("Domain name must be a string: #{inspect(name)}")

  @doc "Adds a compound task to the domain."
  @spec compound(Builder.t(), String.t(), keyword()) :: Builder.t()
  def compound(%Builder{domain: domain, error: nil} = builder, name, opts) when is_binary(name) do
    methods = opts |> Keyword.get(:methods, [])
    Logger.debug("Adding compound task", task_name: name, method_count: length(methods))

    if Map.has_key?(domain.tasks, name) do
      task_exists_error(name)
    else
      methods = Enum.map(methods, &normalize_method/1)
      task = CompoundTask.new!(name, methods)
      %{builder | domain: %{domain | tasks: Map.put(domain.tasks, name, task)}}
    end
  end

  def compound(%Builder{error: nil}, name, _), do: invalid_input("Invalid task name", name)
  def compound(builder, _, _), do: builder

  @doc "Adds a primitive task to the domain."
  @spec primitive(Builder.t(), String.t(), {atom(), keyword()}, keyword()) :: Builder.t()
  def primitive(%Builder{domain: domain, error: nil} = builder, name, {action, params}, opts)
      when is_binary(name) and is_atom(action) do
    Logger.debug("Adding primitive task", task_name: name, action: action)

    if Map.has_key?(domain.tasks, name) do
      task_exists_error(name)
    else
      primitive_task =
        PrimitiveTask.new!(name, {action, params}, normalize_primitive_task_opts(opts))

      %{builder | domain: %{domain | tasks: Map.put(domain.tasks, name, primitive_task)}}
    end
  end

  def primitive(%Builder{domain: domain, error: nil} = builder, name, action, opts) do
    Logger.debug("Adding primitive task", task_name: name, action: action)

    if Map.has_key?(domain.tasks, name) do
      task_exists_error(name)
    else
      primitive_task = PrimitiveTask.new!(name, {action, []}, normalize_primitive_task_opts(opts))
      %{builder | domain: %{domain | tasks: Map.put(domain.tasks, name, primitive_task)}}
    end
  end

  def primitive(%Builder{error: nil}, name, _, _) when not is_binary(name),
    do: invalid_input("Invalid task name", name)

  def primitive(%Builder{error: nil}, _, {action, _}, _) when not is_atom(action),
    do: invalid_input("Invalid action", action)

  def primitive(builder, _, _, _), do: builder

  @doc "Marks a task as a root task in the domain."
  @spec root(Builder.t(), String.t()) :: Builder.t()
  def root(%Builder{domain: domain, error: nil} = builder, name) when is_binary(name) do
    Logger.debug("Marking task as root", task_name: name)

    case Map.get(domain.tasks, name) do
      nil ->
        raise ArgumentError, "Cannot mark '#{name}' as root: task not found"

      %CompoundTask{} ->
        %{builder | domain: %{domain | root_tasks: MapSet.put(domain.root_tasks, name)}}

      _ ->
        raise ArgumentError, "Cannot mark '#{name}' as root: must be a compound task"
    end
  end

  def root(%Builder{error: nil}, name), do: invalid_input("Invalid task name", name)
  def root(builder, _), do: builder

  @doc "Allows an workflow to be used in the domain."
  @spec allow(Builder.t(), String.t(), module()) :: Builder.t()
  def allow(%Builder{domain: domain, error: nil} = builder, name, module)
      when is_binary(name) and is_atom(module) do
    Logger.debug("Allowing workflow", workflow_name: name, module: module)

    %{
      builder
      | domain: %{domain | allowed_workflows: Map.put(domain.allowed_workflows, name, module)}
    }
  end

  def allow(%Builder{error: nil}, name, _) when not is_binary(name),
    do: invalid_input("Invalid workflow name", name)

  def allow(%Builder{error: nil}, _, module) when not is_atom(module),
    do: invalid_input("Invalid workflow module", module)

  def allow(builder, _, _), do: builder

  @doc "Adds a callback to the domain."
  @spec callback(Builder.t(), String.t(), (map() -> boolean()) | (map() -> map())) :: Builder.t()
  def callback(%Builder{domain: domain, error: nil} = builder, name, callback)
      when is_binary(name) and is_function(callback, 1) do
    Logger.debug("Adding callback", callback_name: name)

    %{builder | domain: %{domain | callbacks: Map.put(domain.callbacks, name, callback)}}
  end

  def callback(%Builder{error: nil}, name, _) when not is_binary(name),
    do: invalid_input("Invalid callback name", name)

  def callback(%Builder{error: nil}, _, callback) when not is_function(callback, 1),
    do: invalid_input("Invalid callback function", callback)

  def callback(builder, _, _), do: builder

  @doc "Replaces a task in the domain with a new task."
  @spec replace(Domain.t(), String.t(), CompoundTask.t() | PrimitiveTask.t()) ::
          {:ok, Domain.t()} | {:error, String.t()}
  def replace(%Domain{} = domain, name, new_task)
      when is_binary(name) and
             (is_struct(new_task, CompoundTask) or is_struct(new_task, PrimitiveTask)) do
    Logger.debug("Replacing task", task_name: name)

    tasks = Map.get(domain, :tasks, %{})

    if Map.has_key?(tasks, name) do
      {:ok, %{domain | tasks: Map.put(tasks, name, new_task)}}
    else
      {:error, "Task '#{name}' not found"}
    end
  end

  def replace(_, _, _), do: {:error, "Invalid arguments for replace"}

  @doc """
  Builds the final domain or returns an error.

  ## Options

  - `:validate` - Boolean flag to enable default domain validation. Defaults to `false`.
    When `true`, runs the default validation before any custom validators.

  - `:custom_validators` - List of validator functions that conform to the
    `Jido.HTN.Domain.Builder.Validator` behaviour. Each validator receives
    the domain and returns `:ok`, `{:ok, domain}`, or `{:error, reason}`.
    When provided, custom validators run after default validation (if enabled).
    The validation chain stops at the first error.

  ## Examples

      # Build without validation (default behavior)
      domain =
        Domain.new("example")
        |> Domain.primitive("task1", MyAction)
        |> Domain.build()

      # Build with default validation enabled
      domain =
        Domain.new("example")
        |> Domain.compound("task1", methods: [...])
        |> Domain.root("task1")
        |> Domain.build(validate: true)

      # Build with custom validator only (no default validation)
      domain =
        Domain.new("example")
        |> Domain.compound("task1", methods: [...])
        |> Domain.build(custom_validators: [&MyValidator.validate/1])

      # Build with both default and custom validation
      domain =
        Domain.new("example")
        |> Domain.compound("task1", methods: [...])
        |> Domain.root("task1")
        |> Domain.build(
          validate: true,
          custom_validators: [
            &Validator1.validate/1,
            &Validator2.validate/1
          ]
        )
  """
  @spec build(Builder.t(), keyword()) :: {:ok, Domain.t()} | {:error, String.t() | [String.t()]}
  def build(builder, opts \\ [])

  def build(%Builder{error: error}, _opts) when not is_nil(error), do: {:error, error}

  def build(%Builder{domain: domain, error: nil}, opts) do
    # Get options
    custom_validators = Keyword.get(opts, :custom_validators, [])
    validate? = Keyword.get(opts, :validate, false)

    # Only run validators if requested or if custom validators are provided
    if validate? or custom_validators != [] do
      Logger.debug("Building domain with validation")

      # Build the validator pipeline
      validators =
        if validate? do
          [(&Domain.ValidationHelpers.validate/1) | custom_validators]
        else
          custom_validators
        end

      # Run validators sequentially, stopping at first error
      Enum.reduce_while(validators, {:ok, domain}, fn validator_fun, {:ok, current_domain} ->
        case validator_fun.(current_domain) do
          :ok ->
            {:cont, {:ok, current_domain}}

          {:ok, validated_domain} ->
            {:cont, {:ok, validated_domain}}

          {:error, _reason} = err ->
            {:halt, err}
        end
      end)
    else
      {:ok, domain}
    end
  end

  @spec build!(Builder.t(), keyword()) :: Domain.t()
  def build!(builder, opts \\ [])

  def build!(%Builder{} = builder, opts) do
    case build(builder, opts) do
      {:ok, domain} ->
        domain

      {:error, errors} when is_list(errors) ->
        raise Enum.join(errors, "\n")

      {:error, error} when is_binary(error) ->
        raise error

      {:error, error} ->
        raise inspect(error)
    end
  end

  # Private helper functions

  defp normalize_method(%{conditions: conditions, subtasks: subtasks} = method) do
    # Start with base attrs
    attrs = %{
      conditions: Enum.map(conditions, &normalize_condition/1),
      subtasks: subtasks,
      ordering: Map.get(method, :ordering, [])
    }

    # Only add optional fields if they have values
    attrs =
      if Map.has_key?(method, :name) and method.name != nil do
        Map.put(attrs, :name, method.name)
      else
        attrs
      end

    attrs =
      if Map.has_key?(method, :priority) and method.priority != nil do
        Map.put(attrs, :priority, method.priority)
      else
        attrs
      end

    normalized = Method.new!(attrs)

    # Validate ordering constraints before returning
    Method.validate_ordering!(normalized)
    normalized
  end

  defp normalize_method(method) when is_map(method) do
    normalize_method(%{
      name: Map.get(method, :name),
      priority: Map.get(method, :priority),
      conditions: Map.get(method, :conditions, []),
      subtasks: Map.get(method, :subtasks, []),
      ordering: Map.get(method, :ordering, [])
    })
  end

  defp normalize_method(method), do: method

  defp normalize_condition(condition)
       when is_boolean(condition) or is_binary(condition) or is_function(condition, 1),
       do: condition

  defp normalize_primitive_task_opts(opts) do
    opts
  end

  defp task_exists_error(name),
    do: Builder.error!("Task name '#{name}' already exists in the domain")

  defp invalid_input(msg, value),
    do: Builder.error!("#{msg}: #{inspect(value)}")
end
