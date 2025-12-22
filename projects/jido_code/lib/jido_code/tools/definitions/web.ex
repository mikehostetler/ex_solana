defmodule JidoCode.Tools.Definitions.Web do
  @moduledoc """
  Tool definitions for web operations.

  This module defines the tools for web operations (fetching content,
  searching) that can be registered with the Registry and used by the LLM agent.

  ## Available Tools

  - `web_fetch` - Fetch and parse web content
  - `web_search` - Search the web

  ## Security

  Web tools are subject to domain allowlist restrictions. By default,
  only documentation and code hosting sites are allowed.

  ## Usage

      # Register all web tools
      for tool <- Web.all() do
        :ok = Registry.register(tool)
      end
  """

  alias JidoCode.Tools.Handlers.Web, as: Handlers
  alias JidoCode.Tools.Tool

  @doc """
  Returns all web tools.

  ## Returns

  List of `%Tool{}` structs ready for registration.
  """
  @spec all() :: [Tool.t()]
  def all do
    [
      web_fetch(),
      web_search()
    ]
  end

  @doc """
  Returns the web_fetch tool definition.

  Fetches content from a URL, converts HTML to markdown, and returns
  structured results.

  ## Parameters

  - `url` (required, string) - The URL to fetch
  - `prompt` (optional, string) - Prompt for content extraction (future feature)
  """
  @spec web_fetch() :: Tool.t()
  def web_fetch do
    Tool.new!(%{
      name: "web_fetch",
      description:
        "Fetch content from a URL and convert HTML to readable markdown. " <>
          "Use for reading documentation pages, blog posts, and other web content. " <>
          "Subject to domain allowlist (default: hexdocs.pm, elixir-lang.org, erlang.org, github.com, hex.pm).",
      handler: Handlers.Fetch,
      parameters: [
        %{
          name: "url",
          type: :string,
          description: "The URL to fetch (must be in allowed domains)",
          required: true
        },
        %{
          name: "prompt",
          type: :string,
          description: "Optional prompt describing what information to extract",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the web_search tool definition.

  Searches the web using DuckDuckGo and returns results.

  ## Parameters

  - `query` (required, string) - Search query
  - `num_results` (optional, integer) - Maximum results to return (default: 10, max: 20)
  """
  @spec web_search() :: Tool.t()
  def web_search do
    Tool.new!(%{
      name: "web_search",
      description:
        "Search the web for information using DuckDuckGo. " <>
          "Returns search results with titles, URLs, and snippets. " <>
          "Use for finding documentation, tutorials, or researching topics.",
      handler: Handlers.Search,
      parameters: [
        %{
          name: "query",
          type: :string,
          description: "Search query (e.g., 'Elixir GenServer tutorial')",
          required: true
        },
        %{
          name: "num_results",
          type: :integer,
          description: "Maximum number of results to return (default: 10, max: 20)",
          required: false
        }
      ]
    })
  end
end
