defmodule Jido.Character.Renderer do
  @moduledoc """
  Behaviour and dispatcher for character renderers.

  A renderer transforms a character map into:
  - A system prompt string (`to_system_prompt/2`)
  - A `ReqLLM.Context` struct (`to_context/2`)

  ## Configuration Priority

  Renderers are resolved in this order:
  1. Per-call options (`:renderer` key)
  2. Global application config
  3. Built-in Markdown renderer (default)

  ## Global Configuration

      # config/config.exs
      config :jido_character, Jido.Character.Renderer,
        renderer: MyApp.CustomRenderer,
        renderer_opts: [format: :json]

  ## Implementing a Custom Renderer

      defmodule MyApp.CustomRenderer do
        @behaviour Jido.Character.Renderer

        @impl true
        def to_system_prompt(character, opts) do
          # Return a string prompt
          "You are \#{character.name}..."
        end

        @impl true
        def to_context(character, opts) do
          # Return a ReqLLM.Context
          prompt = to_system_prompt(character, opts)
          ReqLLM.Context.new([ReqLLM.Context.system(prompt)])
        end
      end

  The `to_context/2` callback is optional. If not implemented, the dispatcher
  will wrap the result of `to_system_prompt/2` in a `ReqLLM.Context`.
  """

  alias ReqLLM.Context

  @type character :: map()
  @type opts :: keyword()

  @doc "Render a character to a system prompt string."
  @callback to_system_prompt(character(), opts()) :: String.t()

  @doc "Render a character to a ReqLLM.Context struct."
  @callback to_context(character(), opts()) :: Context.t()

  @optional_callbacks to_context: 2

  @default_renderer Jido.Character.Context.Renderer

  # ---------------------------------------------------------------------------
  # Public Dispatcher API
  # ---------------------------------------------------------------------------

  @doc """
  Render a character to a system prompt string.

  ## Options

  - `:renderer` - Module implementing `Jido.Character.Renderer` behaviour
  - `:renderer_opts` - Options passed to the renderer

  ## Examples

      prompt = Jido.Character.Renderer.to_system_prompt(character)
      prompt = Jido.Character.Renderer.to_system_prompt(character, renderer: MyCustomRenderer)
  """
  @spec to_system_prompt(character(), opts()) :: String.t()
  def to_system_prompt(character, opts \\ []) do
    {renderer, renderer_opts} = resolve_renderer(opts)
    renderer.to_system_prompt(character, renderer_opts)
  end

  @doc """
  Render a character to a ReqLLM.Context struct.

  If the renderer doesn't implement `to_context/2`, falls back to wrapping
  the system prompt from `to_system_prompt/2`.

  ## Options

  - `:renderer` - Module implementing `Jido.Character.Renderer` behaviour
  - `:renderer_opts` - Options passed to the renderer

  ## Examples

      context = Jido.Character.Renderer.to_context(character)
      context = Jido.Character.Renderer.to_context(character, renderer: MyCustomRenderer)
  """
  @spec to_context(character(), opts()) :: Context.t()
  def to_context(character, opts \\ []) do
    {renderer, renderer_opts} = resolve_renderer(opts)

    if function_exported?(renderer, :to_context, 2) do
      renderer.to_context(character, renderer_opts)
    else
      prompt = renderer.to_system_prompt(character, renderer_opts)
      Context.new([Context.system(prompt)])
    end
  end

  @doc """
  Returns the default renderer module.
  """
  @spec default_renderer() :: module()
  def default_renderer do
    global_config()[:renderer] || @default_renderer
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp resolve_renderer(opts) do
    global = global_config()

    renderer =
      Keyword.get(opts, :renderer) ||
        Keyword.get(global, :renderer) ||
        @default_renderer

    renderer_opts =
      Keyword.merge(
        Keyword.get(global, :renderer_opts, []),
        Keyword.get(opts, :renderer_opts, [])
      )

    {renderer, renderer_opts}
  end

  defp global_config do
    Application.get_env(:jido_character, __MODULE__, [])
  end
end
