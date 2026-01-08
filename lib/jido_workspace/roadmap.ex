defmodule JidoWorkspace.Roadmap do
  @moduledoc """
  Roadmap workflow engine for turning ROADMAP.md items into PRs.

  ## Workflow Steps

  1. **Bootstrap** - Parse ROADMAP.md → create item folders
  2. **Research** - `/research {overview}` → research.md
  3. **Plan** - `/plan {research.md}` → plan.md + prd.yaml
  4. **Checkout** - Claim item, create branch, generate prompt.md
  5. **Implement** - Ralph loop on branch
  6. **PR** - `gh pr create` → update item.yaml
  7. **Complete** - Mark done in item.yaml

  ## States

  `raw` → `researched` → `planned` → `checked_out` → `implementing` → `in_pr` → `done`

  ## Storage

  Items and PRDs are stored in YAML (default) or JSON format, configurable via:

      config :jido_workspace, :roadmap, format: :yaml
  """

  require Logger

  alias JidoWorkspace.Roadmap.Store

  @roadmap_dir ".roadmap"

  @doc """
  Returns the base path for the roadmap directory.
  """
  def base_path do
    Path.join(File.cwd!(), @roadmap_dir)
  end

  @doc """
  Returns the path to the index file (legacy, use Store.load_index).
  """
  def index_path do
    Path.join(base_path(), "index.json")
  end

  @doc """
  Load the index file.
  """
  def load_index do
    Store.load_index()
  end

  @doc """
  Save the index file.
  """
  def save_index(index) do
    Store.save_index(index)
  end

  @doc """
  Load an item by its ID (folder path relative to .roadmap/).
  """
  def load_item(item_id) do
    Store.load_task(item_id)
  end

  @doc """
  Save an item.
  """
  def save_item(item) do
    Store.save_task(item)
  end

  @doc """
  List all items from the index.
  """
  def list_items do
    load_index() |> Map.get("items", [])
  end

  @doc """
  Generate a slug from a title.
  """
  def slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.slice(0, 40)
    |> String.trim("-")
  end

  @doc """
  Valid state transitions.
  """
  def valid_transition?(from, to) do
    transitions = %{
      "raw" => ["researched"],
      "researched" => ["planned"],
      "planned" => ["checked_out"],
      "checked_out" => ["implementing"],
      "implementing" => ["in_pr"],
      "in_pr" => ["done"]
    }

    to in Map.get(transitions, from, [])
  end

  @doc """
  Transition an item to a new state.
  """
  def transition_item(item, new_state) do
    if valid_transition?(item["state"], new_state) do
      {:ok, Map.put(item, "state", new_state)}
    else
      {:error, "Invalid transition from #{item["state"]} to #{new_state}"}
    end
  end
end
