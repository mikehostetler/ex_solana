# Example: Custom Validator for HTN Domain
#
# This example demonstrates how to create and use custom validators
# to extend domain validation beyond the default rules.

alias Jido.HTN.Domain

# Define a simple action for testing
defmodule ExampleAction do
  def run(_params, _state, _opts), do: {:ok, %{result: "done"}}
end

# Example 1: Simple validation based on domain properties
defmodule TaskCountValidator do
  @behaviour Jido.HTN.Domain.Builder.Validator

  @impl true
  def validate(%Domain{tasks: tasks} = domain) do
    task_count = map_size(tasks)

    cond do
      task_count < 2 ->
        {:error, "Domain must have at least 2 tasks"}

      task_count > 100 ->
        {:error, "Domain cannot have more than 100 tasks"}

      true ->
        {:ok, domain}
    end
  end
end

# Example 2: Validator that enforces naming conventions
defmodule NamingConventionValidator do
  @behaviour Jido.HTN.Domain.Builder.Validator

  @impl true
  def validate(%Domain{tasks: tasks} = domain) do
    invalid_names =
      tasks
      |> Map.keys()
      |> Enum.filter(fn name ->
        # Enforce convention: all task names must start with lowercase
        first_char = String.at(name, 0)
        first_char != String.downcase(first_char)
      end)

    if Enum.empty?(invalid_names) do
      {:ok, domain}
    else
      {:error, "Tasks with invalid names: #{Enum.join(invalid_names, ", ")}"}
    end
  end
end

# Example 3: Validator that transforms the domain
defmodule MetadataValidator do
  @behaviour Jido.HTN.Domain.Builder.Validator

  @impl true
  def validate(%Domain{} = domain) do
    # Could add metadata or perform transformations
    # For this example, just validate and pass through
    {:ok, domain}
  end
end

# Build a domain with custom validators
IO.puts("\n=== Example 1: Valid Domain with Custom Validators ===")

case Domain.new("shopping_domain")
     |> Domain.allow("purchase", ExampleAction)
     |> Domain.primitive("buy_milk", ExampleAction)
     |> Domain.primitive("buy_bread", ExampleAction)
     |> Domain.compound("do_shopping",
       methods: [
         %{
           name: "method1",
           conditions: [],
           subtasks: ["buy_milk", "buy_bread"]
         }
       ]
     )
     |> Domain.root("do_shopping")
     |> Domain.build(
       validate: false,  # Skip default validation for this example
       custom_validators: [
         &TaskCountValidator.validate/1,
         &NamingConventionValidator.validate/1,
         &MetadataValidator.validate/1
       ]
     ) do
  {:ok, domain} ->
    IO.puts("✓ Domain built successfully!")
    IO.puts("  - Name: #{domain.name}")
    IO.puts("  - Tasks: #{map_size(domain.tasks)}")

  {:error, reason} ->
    IO.puts("✗ Validation failed: #{reason}")
end

# Example showing validation failure
IO.puts("\n=== Example 2: Domain Failing Custom Validation ===")

case Domain.new("small_domain")
     |> Domain.allow("action", ExampleAction)
     |> Domain.primitive("single_task", ExampleAction)
     |> Domain.build(custom_validators: [&TaskCountValidator.validate/1]) do
  {:ok, _domain} ->
    IO.puts("✓ Domain built successfully!")

  {:error, reason} ->
    IO.puts("✗ Validation failed: #{reason}")
end

# Example with inline anonymous validator
IO.puts("\n=== Example 3: Inline Anonymous Validator ===")

max_task_count_validator = fn %Domain{tasks: tasks} = domain ->
  if map_size(tasks) <= 5 do
    {:ok, domain}
  else
    {:error, "Domain is too complex for this example"}
  end
end

case Domain.new("inline_domain")
     |> Domain.allow("action", ExampleAction)
     |> Domain.primitive("task1", ExampleAction)
     |> Domain.primitive("task2", ExampleAction)
     |> Domain.build(custom_validators: [max_task_count_validator]) do
  {:ok, domain} ->
    IO.puts("✓ Domain built successfully!")
    IO.puts("  - Task count: #{map_size(domain.tasks)}")

  {:error, reason} ->
    IO.puts("✗ Validation failed: #{reason}")
end

# Example combining default validation with custom validators
IO.puts("\n=== Example 4: Default + Custom Validation ===")

case Domain.new("validated_domain")
     |> Domain.allow("action", ExampleAction)
     |> Domain.primitive("task1", ExampleAction)
     |> Domain.primitive("task2", ExampleAction)
     |> Domain.compound("main",
       methods: [
         %{
           name: "method1",
           conditions: [],
           subtasks: ["task1", "task2"]
         }
       ]
     )
     |> Domain.root("main")
     |> Domain.build(
       validate: true,  # Enable default validation
       custom_validators: [&TaskCountValidator.validate/1]
     ) do
  {:ok, domain} ->
    IO.puts("✓ Domain passed both default and custom validation!")
    IO.puts("  - Root tasks: #{MapSet.size(domain.root_tasks)}")

  {:error, reason} ->
    IO.puts("✗ Validation failed: #{inspect(reason)}")
end

IO.puts("\n=== Examples Complete ===\n")
