defmodule JidoCode do
  @moduledoc """
  JidoCode - Agentic Coding Assistant TUI

  An intelligent coding assistant built on the Jido autonomous agent framework,
  combining Chain-of-Thought reasoning with a terminal user interface.

  ## Architecture

  JidoCode consists of several layers:

  - **TUI Layer** - Elm Architecture terminal interface via TermUI
  - **Agent Layer** - Jido-based agents for LLM interaction and tool execution
  - **Tool Layer** - Lua-sandboxed tool execution for file operations and shell commands
  - **Knowledge Layer** - RDF-based knowledge graph for context management

  ## Getting Started

  Configure your LLM provider in `config/runtime.exs` or via environment variables:

      export JIDO_CODE_PROVIDER=anthropic
      export JIDO_CODE_MODEL=claude-3-5-sonnet-20241022
      export ANTHROPIC_API_KEY=your_key_here

  Then start the application:

      mix run --no-halt

  """

  @doc """
  Returns the current version of JidoCode.
  """
  def version do
    Application.spec(:jido_code, :vsn) |> to_string()
  end
end
