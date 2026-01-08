defmodule Mix.Tasks.Roadmap.Bootstrap do
  @moduledoc """
  Parse ROADMAP.md and create item folders for each unchecked bullet.

  ## Usage

      mix roadmap.bootstrap
      mix roadmap.bootstrap --file path/to/ROADMAP.md

  Creates numbered folders under `.roadmap/` with `item.yaml` (or `item.json`) files.

  ## Structured Format Support

  The parser supports multiple checkbox formats:
  - `- [ ] Task title` (standard markdown)
  - `* [ ] Task title` (bullet with checkbox)
  - `* \\[ \\] Task title` (escaped brackets)

  Section hierarchy is automatically tracked from markdown headers.
  """

  use Mix.Task
  require Logger

  alias JidoWorkspace.Roadmap
  alias JidoWorkspace.Roadmap.Parser
  alias JidoWorkspace.Roadmap.Store

  @shortdoc "Bootstrap roadmap items from ROADMAP.md"

  @switches [file: :string]

  def run(args) do
    {opts, _} = OptionParser.parse!(args, switches: @switches)

    roadmap_file = opts[:file] || "ROADMAP.md"

    unless File.exists?(roadmap_file) do
      Mix.raise("Roadmap file not found: #{roadmap_file}")
    end

    Logger.info("Bootstrapping from #{roadmap_file}...")

    case Parser.parse_file(roadmap_file) do
      {:ok, roadmap_file_struct} ->
        unchecked_tasks =
          roadmap_file_struct.tasks
          |> Enum.reject(& &1.completed)

        Logger.info("Found #{length(unchecked_tasks)} unchecked items")

        items =
          unchecked_tasks
          |> Enum.with_index(1)
          |> Enum.map(fn {task, number} -> build_item_from_task(task, number) end)

        created = Enum.map(items, &create_item_folder/1)
        success_count = Enum.count(created, &match?({:ok, _}, &1))

        update_index(items)

        Logger.info("Created #{success_count} item folders")
        Mix.shell().info("Run `mix roadmap.workflow.status` to see items")

      {:error, reason} ->
        Mix.raise("Failed to parse roadmap file: #{inspect(reason)}")
    end
  end

  defp build_item_from_task(task, number) do
    section = task.section || []
    title = task.title

    section_slug = section |> Enum.map(&Roadmap.slugify/1) |> Enum.join("/")
    title_slug = Roadmap.slugify(title)
    number_str = String.pad_leading(Integer.to_string(number), 3, "0")

    id =
      if section_slug == "" do
        "#{number_str}-#{title_slug}"
      else
        "#{section_slug}/#{number_str}-#{title_slug}"
      end

    %{
      "id" => id,
      "number" => number,
      "title" => title,
      "overview" => "",
      "section" => section,
      "state" => "raw",
      "branch" => nil,
      "assignee" => nil,
      "pr_url" => nil,
      "roadmap_line" => task.line_number
    }
  end

  defp create_item_folder(item) do
    item_dir = Path.join(Roadmap.base_path(), item["id"])

    if File.exists?(item_dir) do
      Logger.info("Skipping existing: #{item["id"]}")
      {:ok, item["id"]}
    else
      File.mkdir_p!(item_dir)
      # Convert string keys to atom keys for new Store API
      atom_item = atomize_keys(item)
      Store.save_task(atom_item)
      Logger.info("Created: #{item["id"]}")
      {:ok, item["id"]}
    end
  end

  defp update_index(items) do
    case Store.load_index() do
      {:ok, index} ->
        item_ids = Enum.map(items, & &1["id"])
        updated_items = Enum.uniq(index.items ++ item_ids)
        Store.save_index(%{index | items: updated_items})

      {:error, _} ->
        # Index doesn't exist, create it
        item_ids = Enum.map(items, & &1["id"])

        Store.save_index(%{
          version: "1.0.0",
          created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          items: item_ids
        })
    end
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), atomize_keys(v)}
      {k, v} -> {k, atomize_keys(v)}
    end)
  end

  defp atomize_keys(list) when is_list(list), do: Enum.map(list, &atomize_keys/1)
  defp atomize_keys(other), do: other
end
