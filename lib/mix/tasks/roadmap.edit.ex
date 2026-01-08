defmodule Mix.Tasks.Roadmap.Edit do
  @moduledoc """
  Edit fields in a roadmap item's item.json.

  ## Usage

      mix roadmap.edit <item-id> --field <field> --value <value>
      mix roadmap.edit <item-id> --overview "Detailed description..."
      mix roadmap.edit <item-id> --assignee "@mhostetler"
      mix roadmap.edit <item-id> --kind spike

  ## Editable Fields

  - `overview` - Detailed description of the task
  - `assignee` - Who owns this task (e.g., "@mhostetler")
  - `kind` - Task type: implementation, decision, research, spike, maintenance, chore
  - `title` - Human-readable title (max 200 chars)

  ## Examples

      # Set overview
      mix roadmap.edit jido-workspace-roadmap/ready-to-plan/1-jido-core-20-release/001-hand-review --overview "Review all core modules..."

      # Set assignee
      mix roadmap.edit jido-workspace-roadmap/ready-to-plan/1-jido-core-20-release/001-hand-review --assignee "@mhostetler"

      # Set kind
      mix roadmap.edit jido-workspace-roadmap/ready-to-plan/1-jido-core-20-release/001-hand-review --kind research

      # Generic field/value
      mix roadmap.edit <item-id> --field overview --value "Description..."
  """

  use Mix.Task
  require Logger

  alias JidoWorkspace.Roadmap.Store

  @shortdoc "Edit a roadmap item's fields"

  @editable_fields ~w(overview assignee kind title)
  @switches [
    field: :string,
    value: :string,
    overview: :string,
    assignee: :string,
    kind: :string,
    title: :string
  ]

  def run([item_id | rest]) do
    {opts, _} = OptionParser.parse!(rest, switches: @switches)

    case Store.load_task(item_id) do
      {:ok, task} ->
        updates = collect_updates(opts)

        if updates == %{} do
          Mix.shell().error("No updates provided. Use --overview, --assignee, --kind, --title, or --field/--value")
          Mix.raise("No updates specified")
        end

        apply_updates(task, updates)

      {:error, reason} ->
        Mix.raise("Failed to load item #{item_id}: #{inspect(reason)}")
    end
  end

  def run(_), do: Mix.raise("Usage: mix roadmap.edit <item-id> --<field> <value>")

  defp collect_updates(opts) do
    updates = %{}

    # Direct field options
    updates = if opts[:overview], do: Map.put(updates, :overview, opts[:overview]), else: updates
    updates = if opts[:assignee], do: Map.put(updates, :assignee, opts[:assignee]), else: updates
    updates = if opts[:kind], do: Map.put(updates, :kind, opts[:kind]), else: updates
    updates = if opts[:title], do: Map.put(updates, :title, opts[:title]), else: updates

    # Generic --field/--value
    if opts[:field] && opts[:value] do
      field = String.to_atom(opts[:field])

      if opts[:field] in @editable_fields do
        Map.put(updates, field, opts[:value])
      else
        Mix.raise("Field '#{opts[:field]}' is not editable. Editable fields: #{Enum.join(@editable_fields, ", ")}")
      end
    else
      updates
    end
  end

  defp apply_updates(task, updates) do
    updated_task = Map.merge(task, updates)

    case Store.save_task(updated_task) do
      :ok ->
        Logger.info("Updated item: #{task.id}")

        Enum.each(updates, fn {field, value} ->
          display_value = if String.length(to_string(value)) > 60 do
            String.slice(to_string(value), 0, 60) <> "..."
          else
            value
          end
          Logger.info("  #{field}: #{display_value}")
        end)

      {:error, reason} ->
        Mix.raise("Failed to save item: #{inspect(reason)}")
    end
  end
end
