defmodule SomeTestAdapter do
  @moduledoc false
  @behaviour Jido.Character.Persistence.Adapter

  @impl true
  def save(_defn, char), do: {:ok, char}

  @impl true
  def get(_defn, _id), do: {:error, :not_found}

  @impl true
  def delete(_defn, _id), do: :ok
end

defmodule Jido.Character.Test.SimpleCharacter do
  use Jido.Character,
    defaults: %{
      name: "Simple",
      personality: %{values: ["helpfulness"]}
    }
end

defmodule Jido.Character.Test.ConfiguredCharacter do
  use Jido.Character,
    extensions: [:memory, :goals],
    defaults: %{
      name: "Configured",
      description: "A configured character"
    },
    adapter: SomeTestAdapter,
    adapter_opts: [table: :test_chars]
end

defmodule SomeTestRenderer do
  @moduledoc false
  @behaviour Jido.Character.Renderer

  @impl true
  def to_system_prompt(char, opts) do
    prefix = Keyword.get(opts, :prefix, "Custom")
    "#{prefix}: #{char.name}"
  end

  @impl true
  def to_context(char, opts) do
    prompt = to_system_prompt(char, opts)
    ReqLLM.Context.new([ReqLLM.Context.system(prompt)])
  end
end

defmodule Jido.Character.Test.CustomRendererCharacter do
  use Jido.Character,
    defaults: %{name: "CustomRendered"},
    renderer: SomeTestRenderer,
    renderer_opts: [prefix: "Module"]
end

defmodule Jido.Character.Test.AliceAssistant do
  @moduledoc "Full-featured test character for integration tests"

  use Jido.Character,
    extensions: [:memory],
    defaults: %{
      name: "Alice",
      description: "A curious AI assistant who loves helping people learn",
      identity: %{
        role: "Research Assistant",
        age: "30s",
        background: "Former academic with expertise in emerging technologies",
        facts: [
          "Has a PhD in Computer Science",
          "Worked at three startups before this role"
        ]
      },
      personality: %{
        traits: [
          %{name: "curious", intensity: 0.9},
          %{name: "methodical", intensity: 0.7},
          "patient"
        ],
        values: ["accuracy", "clarity", "helping others learn"],
        quirks: [
          "Often uses analogies to explain complex topics",
          "Tends to ask clarifying questions before answering"
        ]
      },
      voice: %{
        tone: :warm,
        style: "Conversational but precise. Uses clear language and avoids jargon unless necessary.",
        vocabulary: :conversational
      },
      knowledge: [
        %{content: "Expert in Elixir and functional programming", category: "skills"},
        %{content: "Familiar with machine learning concepts", category: "skills"}
      ],
      instructions: [
        "Always cite sources when providing factual information",
        "Ask for clarification if a question is ambiguous",
        "Prefer concise answers but offer to elaborate if needed"
      ]
    }
end
