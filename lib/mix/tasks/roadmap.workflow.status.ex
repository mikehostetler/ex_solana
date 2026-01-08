defmodule Mix.Tasks.Roadmap.Workflow.Status do
  @moduledoc """
  Show status of all roadmap workflow items.

  ## Usage

      mix roadmap.workflow.status
      mix roadmap.workflow.status --state planned
      mix roadmap.workflow.status --assignee alice

  """

  use Mix.Task
  require Logger

  alias JidoWorkspace.Roadmap

  @shortdoc "Show roadmap workflow status"

  @switches [state: :string, assignee: :string, json: :boolean]

  def run(args) do
    {opts, _} = OptionParser.parse!(args, switches: @switches)

    items = load_all_items()

    filtered =
      items
      |> filter_by_state(opts[:state])
      |> filter_by_assignee(opts[:assignee])

    if opts[:json] do
      output_json(filtered)
    else
      output_table(filtered)
    end
  end

  defp load_all_items do
    {:ok, index} = Roadmap.load_index()

    index[:items]
    |> Enum.map(fn id ->
      case Roadmap.load_item(id) do
        {:ok, item} -> item
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp filter_by_state(items, nil), do: items

  defp filter_by_state(items, state) do
    state_atom = String.to_existing_atom(state)
    Enum.filter(items, &(&1[:state] == state_atom))
  rescue
    ArgumentError -> Enum.filter(items, &(to_string(&1[:state]) == state))
  end

  defp filter_by_assignee(items, nil), do: items

  defp filter_by_assignee(items, assignee) do
    Enum.filter(items, &(&1[:assignee] == assignee))
  end

  defp output_table(items) do
    if Enum.empty?(items) do
      Mix.shell().info("No items found.")
    else
      rows =
        Enum.map(items, fn item ->
          [
            String.slice(item[:id] || "", -40, 40),
            String.slice(item[:title] || "", 0, 35),
            to_string(item[:state] || "raw"),
            item[:assignee] || "-",
            item[:branch] || "-"
          ]
        end)

      headers = ["ID", "Title", "State", "Assignee", "Branch"]

      TableRex.quick_render!(rows, headers)
      |> Mix.shell().info()

      # Summary by state
      by_state = Enum.group_by(items, & &1[:state])

      summary =
        [:raw, :researched, :planned, :checked_out, :implementing, :in_pr, :done]
        |> Enum.map(fn state ->
          count = length(Map.get(by_state, state, []))
          "#{state}: #{count}"
        end)
        |> Enum.join(" | ")

      Mix.shell().info("\n#{summary}")
    end
  end

  defp output_json(items) do
    items
    |> Jason.encode!(pretty: true)
    |> Mix.shell().info()
  end
end
