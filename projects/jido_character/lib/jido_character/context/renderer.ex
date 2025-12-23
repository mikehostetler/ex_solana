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
      render_identity(get_field(char, :identity)),
      render_personality(get_field(char, :personality)),
      render_voice(get_field(char, :voice)),
      render_memory(get_field(char, :memory)),
      render_knowledge(get_field(char, :knowledge, [])),
      render_instructions(get_field(char, :instructions, []))
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

  defp get_field(struct_or_map, key, default \\ nil)

  defp get_field(%{__struct__: _} = struct, key, default) do
    Map.get(struct, key, default)
  end

  defp get_field(map, key, default) when is_map(map) do
    Map.get(map, key, default)
  end

  defp render_header(char) do
    name = get_field(char, :name, "Unnamed Character")
    desc = get_field(char, :description)

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

    lines =
      if get_field(identity, :role), do: lines ++ ["- Role: #{get_field(identity, :role)}"], else: lines

    lines =
      if get_field(identity, :age), do: lines ++ ["- Age: #{get_field(identity, :age)}"], else: lines

    lines =
      if get_field(identity, :background),
        do: lines ++ ["- Background: #{get_field(identity, :background)}"],
        else: lines

    facts = get_field(identity, :facts, [])
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

    traits = get_field(personality, :traits, [])

    parts =
      if traits != [] do
        trait_str = traits |> Enum.map(&format_trait/1) |> Enum.join(", ")
        parts ++ ["Traits: #{trait_str}"]
      else
        parts
      end

    values = get_field(personality, :values, [])

    parts =
      if values != [] do
        parts ++ ["Values: #{Enum.join(values, ", ")}"]
      else
        parts
      end

    quirks = get_field(personality, :quirks, [])

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
      if get_field(voice, :tone) do
        tone = get_field(voice, :tone) |> to_string() |> String.capitalize()
        parts ++ ["Tone: #{tone}"]
      else
        parts
      end

    parts =
      if get_field(voice, :style) do
        parts ++ ["Style: #{get_field(voice, :style)}"]
      else
        parts
      end

    parts =
      if get_field(voice, :vocabulary) do
        vocab = get_field(voice, :vocabulary) |> to_string() |> String.capitalize()
        parts ++ ["Vocabulary: #{vocab}"]
      else
        parts
      end

    expressions = get_field(voice, :expressions, [])

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
      |> Enum.filter(&(get_field(&1, :importance, 0.5) >= 0.5))
      |> Enum.take(10)

    if important == [] do
      nil
    else
      memory_lines =
        Enum.map(important, fn entry ->
          "- #{get_field(entry, :content) || entry["content"]}"
        end)

      "## Recent Memories\n\n" <> Enum.join(memory_lines, "\n")
    end
  end

  defp render_memory(_), do: nil

  defp render_knowledge([]), do: nil

  defp render_knowledge(knowledge) do
    lines =
      Enum.map(knowledge, fn item ->
        content = get_field(item, :content) || get_string_key(item, "content")
        category = get_field(item, :category) || get_string_key(item, "category")

        if category do
          "- #{content} (#{category})"
        else
          "- #{content}"
        end
      end)

    "## Knowledge\n\n" <> Enum.join(lines, "\n")
  end

  defp get_string_key(map, key) when is_map(map) and not is_struct(map) do
    Map.get(map, key)
  end

  defp get_string_key(_, _), do: nil

  defp render_instructions([]), do: nil

  defp render_instructions(instructions) do
    lines = Enum.map(instructions, &"- #{&1}")
    "## Instructions\n\n" <> Enum.join(lines, "\n")
  end
end
