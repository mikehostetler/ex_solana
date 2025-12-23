defmodule Jido.Character.RendererTest do
  use ExUnit.Case, async: true

  alias Jido.Character
  alias Jido.Character.Renderer

  # A simple custom renderer for testing
  defmodule TestRenderer do
    @behaviour Jido.Character.Renderer

    @impl true
    def to_system_prompt(character, opts) do
      format = Keyword.get(opts, :format, :simple)

      case format do
        :simple -> "I am #{character.name}"
        :json -> Jason.encode!(%{name: character.name, type: "character"})
      end
    end

    @impl true
    def to_context(character, opts) do
      prompt = to_system_prompt(character, opts)
      ReqLLM.Context.new([ReqLLM.Context.system(prompt)])
    end
  end

  # A renderer that only implements to_system_prompt (to test fallback)
  defmodule MinimalRenderer do
    @behaviour Jido.Character.Renderer

    @impl true
    def to_system_prompt(character, _opts) do
      "Minimal: #{character.name}"
    end
  end

  describe "behaviour" do
    test "defines to_system_prompt callback" do
      assert function_exported?(Renderer, :behaviour_info, 1)
    end
  end

  describe "default_renderer/0" do
    test "returns the default Markdown renderer" do
      assert Renderer.default_renderer() == Jido.Character.Context.Renderer
    end
  end

  describe "to_system_prompt/2" do
    test "uses default renderer when no options provided" do
      {:ok, char} = Character.new(%{name: "Bob"})
      prompt = Renderer.to_system_prompt(char)

      assert prompt =~ "# Character: Bob"
    end

    test "uses custom renderer when specified in options" do
      {:ok, char} = Character.new(%{name: "Bob"})
      prompt = Renderer.to_system_prompt(char, renderer: TestRenderer)

      assert prompt == "I am Bob"
    end

    test "passes renderer_opts to the renderer" do
      {:ok, char} = Character.new(%{name: "Bob"})
      prompt = Renderer.to_system_prompt(char, renderer: TestRenderer, renderer_opts: [format: :json])

      assert prompt == ~s|{"name":"Bob","type":"character"}|
    end
  end

  describe "to_context/2" do
    test "uses default renderer when no options provided" do
      {:ok, char} = Character.new(%{name: "Alice"})
      context = Renderer.to_context(char)

      assert %ReqLLM.Context{} = context
      assert length(context.messages) == 1
      content = get_message_text(context)
      assert content =~ "# Character: Alice"
    end

    test "uses custom renderer when specified in options" do
      {:ok, char} = Character.new(%{name: "Alice"})
      context = Renderer.to_context(char, renderer: TestRenderer)

      assert %ReqLLM.Context{} = context
      assert get_message_text(context) == "I am Alice"
    end

    test "falls back to wrapping system prompt when to_context not implemented" do
      {:ok, char} = Character.new(%{name: "Carol"})
      context = Renderer.to_context(char, renderer: MinimalRenderer)

      assert %ReqLLM.Context{} = context
      assert get_message_text(context) == "Minimal: Carol"
    end
  end

  describe "integration with Jido.Character" do
    test "Character.to_system_prompt uses renderer dispatcher" do
      {:ok, char} = Character.new(%{name: "Test"})
      prompt = Character.to_system_prompt(char, renderer: TestRenderer)

      assert prompt == "I am Test"
    end

    test "Character.to_context uses renderer dispatcher" do
      {:ok, char} = Character.new(%{name: "Test"})
      context = Character.to_context(char, renderer: TestRenderer)

      assert get_message_text(context) == "I am Test"
    end
  end

  # Helper to extract text from message content (handles ContentPart lists)
  defp get_message_text(context) do
    msg = hd(context.messages)

    case msg.content do
      text when is_binary(text) -> text
      parts when is_list(parts) -> Enum.map_join(parts, "", &extract_text/1)
    end
  end

  defp extract_text(%{text: text}), do: text
  defp extract_text(_), do: ""
end
