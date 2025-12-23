defmodule Jido.Character.Context.Renderer do
  @moduledoc """
  Default Markdown renderer for characters.

  Produces Markdown-formatted prompts that effectively communicate
  the character's identity, personality, and behavioral guidelines to an LLM.

  This is the default implementation of `Jido.Character.Renderer`. To use a
  custom renderer, see `Jido.Character.Renderer` for configuration options.
  """

  @behaviour Jido.Character.Renderer

  alias ReqLLM.Context
  import ReqLLM.Context, only: [system: 1]

  @impl true
  @doc "Render a character to a system prompt string."
  @spec to_system_prompt(map(), keyword()) :: String.t()
  def to_system_prompt(%{} = char, _opts \\ []) do
    sections = [
      render_header(char),
      render_identity(Map.get(char, :identity)),
      render_personality(Map.get(char, :personality)),
      render_voice(Map.get(char, :voice)),
      render_memory(Map.get(char, :memory)),
      render_knowledge(Map.get(char, :knowledge, [])),
      render_instructions(Map.get(char, :instructions, []))
    ]

    sections
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  @impl true
  @doc "Render a character to a ReqLLM.Context."
  @spec to_context(map(), keyword()) :: Context.t()
  def to_context(%{} = char, opts \\ []) do
    prompt = to_system_prompt(char, opts)
    Context.new([system(prompt)])
  end

  defp render_header(char) do
    name = Map.get(char, :name, "Unnamed Character")
    desc = Map.get(char, :description)

    header = "# Character: #{name}"

    if desc && String.trim(desc) != "" do
      header <> "\n\n" <> desc
    else
      header
    end
  end

  defp render_identity(nil), do: nil
  defp render_identity(identity) when identity == %{}, do: nil

  defp render_identity(identity) do
    lines = []

    lines = if identity[:role], do: lines ++ ["- Role: #{identity[:role]}"], else: lines
    lines = if identity[:age], do: lines ++ ["- Age: #{identity[:age]}"], else: lines

    lines =
      if identity[:background], do: lines ++ ["- Background: #{identity[:background]}"], else: lines

    facts = Map.get(identity, :facts, [])
    lines = lines ++ Enum.map(facts, &"- #{&1}")

    if lines == [] do
      nil
    else
      "## Identity\n\n" <> Enum.join(lines, "\n")
    end
  end

  defp render_personality(nil), do: nil
  defp render_personality(personality) when personality == %{}, do: nil

  defp render_personality(personality) do
    parts = []

    traits = Map.get(personality, :traits, [])

    parts =
      if traits != [] do
        trait_str = traits |> Enum.map(&format_trait/1) |> Enum.join(", ")
        parts ++ ["Traits: #{trait_str}"]
      else
        parts
      end

    values = Map.get(personality, :values, [])

    parts =
      if values != [] do
        parts ++ ["Values: #{Enum.join(values, ", ")}"]
      else
        parts
      end

    quirks = Map.get(personality, :quirks, [])

    parts =
      if quirks != [] do
        quirk_lines = Enum.map(quirks, &"- #{&1}")
        parts ++ ["Quirks:\n" <> Enum.join(quirk_lines, "\n")]
      else
        parts
      end

    if parts == [] do
      nil
    else
      "## Personality\n\n" <> Enum.join(parts, "\n\n")
    end
  end

  defp format_trait(trait) when is_binary(trait), do: trait

  defp format_trait(%{name: name, intensity: intensity}) do
    level =
      cond do
        intensity >= 0.8 -> "high"
        intensity >= 0.5 -> "moderate"
        true -> "low"
      end

    "#{name} (#{level})"
  end

  defp format_trait(%{"name" => name, "intensity" => intensity}) do
    format_trait(%{name: name, intensity: intensity})
  end

  defp render_voice(nil), do: nil
  defp render_voice(voice) when voice == %{}, do: nil

  defp render_voice(voice) do
    parts = []

    parts =
      if voice[:tone] do
        tone = voice[:tone] |> to_string() |> String.capitalize()
        parts ++ ["Tone: #{tone}"]
      else
        parts
      end

    parts =
      if voice[:style] do
        parts ++ ["Style: #{voice[:style]}"]
      else
        parts
      end

    parts =
      if voice[:vocabulary] do
        vocab = voice[:vocabulary] |> to_string() |> String.capitalize()
        parts ++ ["Vocabulary: #{vocab}"]
      else
        parts
      end

    expressions = Map.get(voice, :expressions, [])

    parts =
      if expressions != [] do
        parts ++ ["Expressions: #{Enum.join(expressions, ", ")}"]
      else
        parts
      end

    if parts == [] do
      nil
    else
      "## Voice\n\n" <> Enum.join(parts, "\n")
    end
  end

  defp render_memory(nil), do: nil
  defp render_memory(%{entries: []}), do: nil

  defp render_memory(%{entries: entries}) when is_list(entries) do
    important =
      entries
      |> Enum.filter(&(Map.get(&1, :importance, 0.5) >= 0.5))
      |> Enum.take(10)

    if important == [] do
      nil
    else
      memory_lines =
        Enum.map(important, fn entry ->
          "- #{entry[:content] || entry["content"]}"
        end)

      "## Recent Memories\n\n" <> Enum.join(memory_lines, "\n")
    end
  end

  defp render_memory(_), do: nil

  defp render_knowledge([]), do: nil

  defp render_knowledge(knowledge) do
    lines =
      Enum.map(knowledge, fn item ->
        content = item[:content] || item["content"]
        category = item[:category] || item["category"]

        if category do
          "- #{content} (#{category})"
        else
          "- #{content}"
        end
      end)

    "## Knowledge\n\n" <> Enum.join(lines, "\n")
  end

  defp render_instructions([]), do: nil

  defp render_instructions(instructions) do
    lines = Enum.map(instructions, &"- #{&1}")
    "## Instructions\n\n" <> Enum.join(lines, "\n")
  end
end
