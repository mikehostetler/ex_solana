defmodule JidoWorkspace.Roadmap.PRD do
  @moduledoc """
  PRD (Product Requirements Document) generation using LLM.

  Replaces the brittle regex-based extraction with structured LLM output.
  """

  alias JidoWorkspace.LLM
  alias JidoWorkspace.Roadmap
  alias JidoWorkspace.Roadmap.Store

  require Logger

  @doc """
  Generate a PRD from an item and its plan markdown.

  Uses the LLM to extract user stories with acceptance criteria,
  returning a structured PRD map.
  """
  def generate(item, plan_md, opts \\ []) do
    use_llm = Keyword.get(opts, :use_llm, true)

    if use_llm do
      generate_with_llm(item, plan_md)
    else
      generate_heuristic(item, plan_md)
    end
  end

  @doc """
  Save a PRD to the item directory.
  """
  def save(item_dir, prd) do
    Store.save_prd(item_dir, prd)
  end

  @doc """
  Load a PRD from the item directory.
  """
  def load(item_dir) do
    Store.load_prd(item_dir)
  end

  defp generate_with_llm(item, plan_md) do
    prompt = build_prd_prompt(item, plan_md)

    case LLM.run_json(prompt) do
      {:ok, prd} ->
        validate_and_normalize(prd, item)

      {:error, reason, raw} ->
        Logger.warning("LLM returned invalid JSON: #{inspect(reason)}")
        Logger.debug("Raw output: #{raw}")
        Logger.info("Falling back to heuristic PRD generation")
        generate_heuristic(item, plan_md)
    end
  end

  defp build_prd_prompt(item, plan_md) do
    """
    You are a product manager extracting user stories from a plan.

    ## Input

    **Item ID:** #{item["id"]}
    **Title:** #{item["title"]}
    **Overview:** #{item["overview"] || item["title"]}

    **Plan:**
    #{plan_md}

    ## Task

    Extract 3-10 concrete user stories representing the implementation work.

    For each story provide:
    - id: "US-001", "US-002", etc.
    - title: Short description (under 80 chars)
    - acceptanceCriteria: 3-7 specific, testable criteria
    - priority: 1 = highest
    - passes: false (default)
    - notes: "" (default)

    Also propose a branchName in kebab-case format: "roadmap/<slug>"

    ## Output

    Return ONLY valid JSON (no markdown fences, no explanation):

    {
      "id": "#{item["id"]}",
      "branchName": "roadmap/example-slug",
      "baseBranch": "main",
      "userStories": [
        {
          "id": "US-001",
          "title": "Example story title",
          "acceptanceCriteria": ["Criterion 1", "Criterion 2"],
          "priority": 1,
          "passes": false,
          "notes": ""
        }
      ]
    }
    """
  end

  defp validate_and_normalize(prd, item) do
    prd
    |> Map.put_new("id", item["id"])
    |> Map.put_new("baseBranch", "main")
    |> Map.update("branchName", "roadmap/#{Roadmap.slugify(item["title"])}", fn
      nil -> "roadmap/#{Roadmap.slugify(item["title"])}"
      "" -> "roadmap/#{Roadmap.slugify(item["title"])}"
      name -> name
    end)
    |> Map.update("userStories", [], &normalize_stories/1)
  end

  defp normalize_stories(stories) when is_list(stories) do
    stories
    |> Enum.with_index(1)
    |> Enum.map(fn {story, idx} ->
      story
      |> Map.put_new("id", "US-#{String.pad_leading(Integer.to_string(idx), 3, "0")}")
      |> Map.put_new("priority", idx)
      |> Map.put_new("passes", false)
      |> Map.put_new("notes", "")
      |> Map.put_new("acceptanceCriteria", ["Implementation complete"])
    end)
  end

  defp normalize_stories(_), do: []

  defp generate_heuristic(item, plan_content) do
    stories =
      plan_content
      |> String.split("\n")
      |> Enum.filter(&numbered_line?/1)
      |> Enum.with_index(1)
      |> Enum.map(fn {line, idx} ->
        title = extract_title(line)

        %{
          "id" => "US-#{String.pad_leading(Integer.to_string(idx), 3, "0")}",
          "title" => title,
          "acceptanceCriteria" => [
            "Implementation complete",
            "Tests pass",
            "Typecheck passes"
          ],
          "priority" => idx,
          "passes" => false,
          "notes" => ""
        }
      end)

    stories =
      if Enum.empty?(stories) do
        [
          %{
            "id" => "US-001",
            "title" => item["title"],
            "acceptanceCriteria" => [
              "Implementation complete",
              "Tests pass",
              "Typecheck passes"
            ],
            "priority" => 1,
            "passes" => false,
            "notes" => ""
          }
        ]
      else
        stories
      end

    %{
      "id" => item["id"],
      "branchName" => "roadmap/#{Roadmap.slugify(item["title"])}",
      "baseBranch" => "main",
      "userStories" => stories
    }
  end

  defp numbered_line?(line) do
    String.match?(line, ~r/^\d+\.\s+/)
  end

  defp extract_title(line) do
    line
    |> String.replace(~r/^\d+\.\s+/, "")
    |> String.trim()
    |> String.slice(0, 80)
  end
end
