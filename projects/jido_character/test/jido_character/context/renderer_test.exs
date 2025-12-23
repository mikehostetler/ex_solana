defmodule Jido.Character.Context.RendererTest do
  use ExUnit.Case, async: true

  alias Jido.Character.Context.Renderer
  alias ReqLLM.Context
  alias ReqLLM.Message

  describe "to_system_prompt/2" do
    test "renders minimal character with just name" do
      char = %{name: "Alex"}
      prompt = Renderer.to_system_prompt(char)

      assert prompt =~ "# Character: Alex"
    end

    test "renders character with description" do
      char = %{
        name: "Alex",
        description: "A curious research assistant specializing in technology"
      }

      prompt = Renderer.to_system_prompt(char)

      assert prompt =~ "# Character: Alex"
      assert prompt =~ "A curious research assistant specializing in technology"
    end

    test "renders identity section" do
      char = %{
        name: "Alex",
        identity: %{
          role: "Research Assistant",
          age: "30s",
          background: "Former academic with expertise in emerging technologies",
          facts: [
            "Has a PhD in Computer Science",
            "Worked at three startups before this role"
          ]
        }
      }

      prompt = Renderer.to_system_prompt(char)

      assert prompt =~ "## Identity"
      assert prompt =~ "- Role: Research Assistant"
      assert prompt =~ "- Age: 30s"
      assert prompt =~ "- Background: Former academic with expertise in emerging technologies"
      assert prompt =~ "- Has a PhD in Computer Science"
      assert prompt =~ "- Worked at three startups before this role"
    end

    test "renders personality section with traits and values" do
      char = %{
        name: "Alex",
        personality: %{
          traits: [
            %{name: "curious", intensity: 0.9},
            %{name: "methodical", intensity: 0.6},
            %{name: "patient", intensity: 0.4}
          ],
          values: ["accuracy", "clarity", "helping others learn"],
          quirks: [
            "Often uses analogies to explain complex topics",
            "Tends to ask clarifying questions before answering"
          ]
        }
      }

      prompt = Renderer.to_system_prompt(char)

      assert prompt =~ "## Personality"
      assert prompt =~ "Traits: curious (high), methodical (moderate), patient (low)"
      assert prompt =~ "Values: accuracy, clarity, helping others learn"
      assert prompt =~ "Quirks:"
      assert prompt =~ "- Often uses analogies to explain complex topics"
      assert prompt =~ "- Tends to ask clarifying questions before answering"
    end

    test "renders simple string traits" do
      char = %{
        name: "Alex",
        personality: %{
          traits: ["curious", "methodical"]
        }
      }

      prompt = Renderer.to_system_prompt(char)
      assert prompt =~ "Traits: curious, methodical"
    end

    test "renders voice section" do
      char = %{
        name: "Alex",
        voice: %{
          tone: :warm,
          style: "Conversational but precise. Uses clear language and avoids jargon unless necessary.",
          vocabulary: :conversational,
          expressions: ["Well, actually...", "Here's the thing..."]
        }
      }

      prompt = Renderer.to_system_prompt(char)

      assert prompt =~ "## Voice"
      assert prompt =~ "Tone: Warm"
      assert prompt =~ "Style: Conversational but precise"
      assert prompt =~ "Vocabulary: Conversational"
      assert prompt =~ "Expressions: Well, actually..., Here's the thing..."
    end

    test "renders knowledge section" do
      char = %{
        name: "Alex",
        knowledge: [
          %{content: "Expert in Elixir and functional programming", category: "skills"},
          %{content: "Familiar with machine learning concepts", category: "skills"}
        ]
      }

      prompt = Renderer.to_system_prompt(char)

      assert prompt =~ "## Knowledge"
      assert prompt =~ "- Expert in Elixir and functional programming (skills)"
      assert prompt =~ "- Familiar with machine learning concepts (skills)"
    end

    test "renders knowledge without category" do
      char = %{
        name: "Alex",
        knowledge: [
          %{content: "General programming knowledge"}
        ]
      }

      prompt = Renderer.to_system_prompt(char)
      assert prompt =~ "- General programming knowledge"
      refute prompt =~ "()"
    end

    test "renders instructions section" do
      char = %{
        name: "Alex",
        instructions: [
          "Always cite sources when providing factual information",
          "Ask for clarification if a question is ambiguous"
        ]
      }

      prompt = Renderer.to_system_prompt(char)

      assert prompt =~ "## Instructions"
      assert prompt =~ "- Always cite sources when providing factual information"
      assert prompt =~ "- Ask for clarification if a question is ambiguous"
    end

    test "renders memory section with important entries" do
      char = %{
        name: "Alex",
        memory: %{
          entries: [
            %{content: "User prefers concise explanations", importance: 0.8},
            %{content: "User mentioned working on an Elixir project", importance: 0.6},
            %{content: "Unimportant detail", importance: 0.3}
          ]
        }
      }

      prompt = Renderer.to_system_prompt(char)

      assert prompt =~ "## Recent Memories"
      assert prompt =~ "- User prefers concise explanations"
      assert prompt =~ "- User mentioned working on an Elixir project"
      refute prompt =~ "Unimportant detail"
    end

    test "omits empty sections" do
      char = %{
        name: "Alex",
        identity: %{},
        personality: %{traits: [], values: [], quirks: []},
        knowledge: [],
        instructions: []
      }

      prompt = Renderer.to_system_prompt(char)

      assert prompt =~ "# Character: Alex"
      refute prompt =~ "## Identity"
      refute prompt =~ "## Personality"
      refute prompt =~ "## Knowledge"
      refute prompt =~ "## Instructions"
    end

    test "handles unnamed character" do
      char = %{}
      prompt = Renderer.to_system_prompt(char)

      assert prompt =~ "# Character: Unnamed Character"
    end

    test "renders full character matching expected format" do
      char = %{
        name: "Alex",
        description: "A curious research assistant specializing in technology",
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
            %{name: "methodical", intensity: 0.6},
            %{name: "patient", intensity: 0.4}
          ],
          values: ["accuracy", "clarity", "helping others learn"],
          quirks: [
            "Often uses analogies to explain complex topics",
            "Tends to ask clarifying questions before answering"
          ]
        },
        voice: %{
          tone: :warm,
          style: "Conversational but precise. Uses clear language and avoids jargon unless necessary."
        },
        knowledge: [
          %{content: "Expert in Elixir and functional programming", category: "skills"},
          %{content: "Familiar with machine learning concepts", category: "skills"}
        ],
        instructions: [
          "Always cite sources when providing factual information",
          "Ask for clarification if a question is ambiguous"
        ]
      }

      prompt = Renderer.to_system_prompt(char)

      assert prompt =~ "# Character: Alex"
      assert prompt =~ "A curious research assistant"
      assert prompt =~ "## Identity"
      assert prompt =~ "## Personality"
      assert prompt =~ "## Voice"
      assert prompt =~ "## Knowledge"
      assert prompt =~ "## Instructions"
    end
  end

  describe "to_context/2" do
    test "returns ReqLLM.Context struct" do
      char = %{name: "Alex"}
      context = Renderer.to_context(char)

      assert %Context{} = context
    end

    test "context contains system message with rendered prompt" do
      char = %{name: "Alex", description: "A helpful assistant"}
      context = Renderer.to_context(char)

      assert [%Message{role: :system} = msg] = context.messages
      text = get_text_content(msg)
      assert text =~ "# Character: Alex"
      assert text =~ "A helpful assistant"
    end

    test "full character renders to valid context" do
      {:ok, char} =
        Jido.Character.new(%{
          name: "Bob",
          description: "Test character",
          identity: %{role: "Tester"},
          personality: %{traits: ["friendly"]},
          voice: %{tone: :casual},
          knowledge: [%{content: "Testing knowledge"}],
          instructions: ["Be helpful"]
        })

      context = Renderer.to_context(char)

      assert %Context{messages: [%Message{role: :system}]} = context
    end
  end

  describe "integration with Jido.Character" do
    test "to_context/2 works through main module" do
      {:ok, char} = Jido.Character.new(%{name: "Test"})
      context = Jido.Character.to_context(char)

      assert %Context{} = context
    end

    test "to_system_prompt/2 works through main module" do
      {:ok, char} = Jido.Character.new(%{name: "Test"})
      prompt = Jido.Character.to_system_prompt(char)

      assert is_binary(prompt)
      assert prompt =~ "# Character: Test"
    end
  end

  defp get_text_content(%Message{content: content}) when is_list(content) do
    content
    |> Enum.map(fn
      %{text: text} -> text
      _ -> ""
    end)
    |> Enum.join("")
  end

  defp get_text_content(%Message{content: content}) when is_binary(content), do: content
end
