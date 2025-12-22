defmodule JidoCode.Tools.Handlers.Web do
  @moduledoc """
  Handler modules for web tools.

  This module contains sub-modules for web operations including fetching
  content and searching the web.

  ## Handler Modules

  - `Fetch` - Fetch and parse web content
  - `Search` - Search the web via API

  ## Session Context

  Web handlers include session_id in result metadata when provided in context.
  This enables:
  - Correlation of web requests with sessions
  - Logging and debugging
  - Consistent handler pattern across all tool types

  Note: Web handlers don't need path validation since they access external URLs.

  ## Security

  All web operations are subject to security validation:
  - Domain allowlist enforcement
  - URL scheme validation
  - Response size limits
  - Request timeout limits

  See `JidoCode.Tools.Security.Web` for configuration.
  """

  alias JidoCode.Tools.Security.Web, as: WebSecurity

  # ============================================================================
  # Shared Helpers
  # ============================================================================

  @doc false
  @spec add_session_metadata(map(), map()) :: map()
  def add_session_metadata(result, %{session_id: session_id}) when is_binary(session_id) do
    Map.put(result, :session_id, session_id)
  end

  def add_session_metadata(result, _context), do: result

  @doc false
  def format_error(:domain_not_allowed, url), do: "Domain not in allowlist: #{url}"
  def format_error(:blocked_scheme, url), do: "URL scheme not allowed: #{url}"
  def format_error(:timeout, url), do: "Request timed out: #{url}"
  def format_error(:too_large, url), do: "Response too large: #{url}"
  def format_error(:invalid_content_type, url), do: "Content type not allowed: #{url}"
  def format_error(:connection_error, url), do: "Failed to connect: #{url}"
  def format_error(reason, url) when is_atom(reason), do: "Web error (#{reason}): #{url}"
  def format_error(reason, _url) when is_binary(reason), do: reason
  def format_error(reason, url), do: "Error (#{inspect(reason)}): #{url}"

  # ============================================================================
  # Fetch Handler
  # ============================================================================

  defmodule Fetch do
    @moduledoc """
    Handler for the web_fetch tool.

    Fetches content from URLs, converts HTML to markdown, and returns
    structured results.

    Includes session_id in result metadata when provided in context.
    """

    alias JidoCode.Tools.Handlers.Web
    alias JidoCode.Tools.Security.Web, as: WebSecurity

    @doc """
    Fetches content from a URL.

    ## Arguments

    - `"url"` - The URL to fetch (required)
    - `"prompt"` - Optional prompt for content extraction (not implemented yet)

    ## Context

    - `:session_id` - Included in result metadata when provided
    - `:allowed_domains` - Custom domain allowlist (optional)

    ## Returns

    - `{:ok, result}` - JSON with url, title, content, and optionally session_id
    - `{:error, reason}` - Error message
    """
    def execute(%{"url" => url} = args, context) when is_binary(url) do
      allowed_domains = get_allowed_domains(context)
      _prompt = Map.get(args, "prompt", nil)

      with {:ok, validated_url} <- WebSecurity.validate_url(url, allowed_domains: allowed_domains),
           :ok <- WebSecurity.log_request(validated_url),
           {:ok, response} <- fetch_url(validated_url),
           {:ok, content} <- process_response(response) do
        result = Web.add_session_metadata(content, context)
        {:ok, Jason.encode!(result)}
      else
        {:error, reason} -> {:error, Web.format_error(reason, url)}
      end
    end

    def execute(_args, _context) do
      {:error, "web_fetch requires a url argument"}
    end

    defp get_allowed_domains(context) do
      Map.get(context, :allowed_domains, WebSecurity.default_allowed_domains())
    end

    defp fetch_url(url) do
      timeout = WebSecurity.default_timeout()
      max_size = WebSecurity.max_response_size()

      req_opts = [
        receive_timeout: timeout,
        max_redirects: WebSecurity.max_redirects(),
        headers: [
          {"user-agent", "JidoCode/1.0 (Elixir coding assistant)"},
          {"accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"}
        ]
      ]

      case Req.get(url, req_opts) do
        {:ok, %Req.Response{status: status, body: body, headers: headers}}
        when status in 200..299 ->
          content_type = get_header(headers, "content-type")

          # Handle pre-decoded JSON (Req auto-decodes JSON)
          {body_str, body_size} =
            cond do
              is_map(body) ->
                encoded = Jason.encode!(body)
                {encoded, byte_size(encoded)}

              is_binary(body) ->
                {body, byte_size(body)}

              true ->
                {inspect(body), 0}
            end

          cond do
            body_size > max_size ->
              {:error, :too_large}

            not WebSecurity.allowed_content_type?(content_type) ->
              {:error, :invalid_content_type}

            true ->
              title = extract_title(body_str)
              {:ok, %{status: status, body: body_str, content_type: content_type, title: title}}
          end

        {:ok, %Req.Response{status: status}} when status in 300..399 ->
          {:error, :too_many_redirects}

        {:ok, %Req.Response{status: status}} ->
          {:error, "HTTP #{status}"}

        {:error, %Req.TransportError{reason: :timeout}} ->
          {:error, :timeout}

        {:error, %Req.TransportError{reason: reason}} ->
          {:error, {:connection_error, reason}}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp get_header(headers, name) when is_map(headers) do
      # Req returns headers as a map with list values
      case Map.get(headers, name) do
        [value | _] -> value
        nil -> ""
      end
    end

    defp get_header(headers, name) when is_list(headers) do
      # Fallback for list-style headers
      case List.keyfind(headers, name, 0) do
        {_, value} -> value
        nil -> ""
      end
    end

    defp extract_title(html) when is_binary(html) do
      case Floki.parse_document(html) do
        {:ok, doc} ->
          case Floki.find(doc, "title") do
            [title_elem | _] -> Floki.text(title_elem) |> String.trim()
            [] -> nil
          end

        _ ->
          nil
      end
    end

    defp process_response(%{body: body, content_type: content_type, title: title}) do
      content =
        if String.contains?(content_type, "html") do
          html_to_markdown(body)
        else
          body
        end

      {:ok,
       %{
         title: title,
         content: content,
         content_type: content_type
       }}
    end

    @doc """
    Converts HTML content to simplified markdown.
    """
    def html_to_markdown(html) when is_binary(html) do
      case Floki.parse_document(html) do
        {:ok, doc} ->
          # Remove script and style tags
          doc =
            doc
            |> Floki.filter_out("script")
            |> Floki.filter_out("style")
            |> Floki.filter_out("nav")
            |> Floki.filter_out("footer")
            |> Floki.filter_out("header")

          # Find main content area
          main_content =
            case Floki.find(doc, "main, article, .content, #content, .main, #main") do
              [content | _] -> content
              [] -> doc
            end

          # Convert to text preserving some structure
          convert_to_markdown(main_content)

        {:error, _} ->
          # If parsing fails, strip tags and return plain text
          html
          |> String.replace(~r/<[^>]+>/, " ")
          |> String.replace(~r/\s+/, " ")
          |> String.trim()
      end
    end

    defp convert_to_markdown(node) when is_binary(node), do: node

    defp convert_to_markdown({tag, _attrs, children}) do
      content = Enum.map_join(children, "", &convert_to_markdown/1)

      case tag do
        "h1" -> "\n# #{String.trim(content)}\n"
        "h2" -> "\n## #{String.trim(content)}\n"
        "h3" -> "\n### #{String.trim(content)}\n"
        "h4" -> "\n#### #{String.trim(content)}\n"
        "h5" -> "\n##### #{String.trim(content)}\n"
        "h6" -> "\n###### #{String.trim(content)}\n"
        "p" -> "\n#{String.trim(content)}\n"
        "br" -> "\n"
        "li" -> "- #{String.trim(content)}\n"
        "code" -> "`#{content}`"
        "pre" -> "\n```\n#{content}\n```\n"
        "strong" -> "**#{content}**"
        "b" -> "**#{content}**"
        "em" -> "*#{content}*"
        "i" -> "*#{content}*"
        # Just keep the text for now
        "a" -> content
        "ul" -> "\n#{content}"
        "ol" -> "\n#{content}"
        "div" -> "\n#{content}"
        "section" -> "\n#{content}"
        "article" -> "\n#{content}"
        "span" -> content
        _ -> content
      end
    end

    defp convert_to_markdown(nodes) when is_list(nodes) do
      Enum.map_join(nodes, "", &convert_to_markdown/1)
    end

    defp convert_to_markdown(_), do: ""
  end

  # ============================================================================
  # Search Handler
  # ============================================================================

  defmodule Search do
    @moduledoc """
    Handler for the web_search tool.

    Searches the web using DuckDuckGo (default) or other configured providers.

    Includes session_id in result metadata when provided in context.
    """

    alias JidoCode.Tools.Handlers.Web

    @default_max_results 10
    @duckduckgo_api "https://api.duckduckgo.com/"

    @doc """
    Searches the web for a query.

    ## Arguments

    - `"query"` - Search query (required)
    - `"num_results"` - Maximum results to return (optional, default 10)

    ## Context

    - `:session_id` - Included in result metadata when provided

    ## Returns

    - `{:ok, results}` - JSON object with results array and optionally session_id
    - `{:error, reason}` - Error message
    """
    def execute(%{"query" => query} = args, context) when is_binary(query) do
      max_results = Map.get(args, "num_results", @default_max_results)
      max_results = min(max_results, 20)

      case search_duckduckgo(query, max_results) do
        {:ok, results} ->
          result = %{results: results}
          result = Web.add_session_metadata(result, context)
          {:ok, Jason.encode!(result)}

        {:error, reason} ->
          {:error, Web.format_error(reason, "search")}
      end
    end

    def execute(_args, _context) do
      {:error, "web_search requires a query argument"}
    end

    defp search_duckduckgo(query, max_results) do
      # Use DuckDuckGo Instant Answer API
      # Note: This returns instant answers, not full search results
      # For full search, would need to parse HTML or use a different API
      url = "#{@duckduckgo_api}?q=#{URI.encode_www_form(query)}&format=json&no_redirect=1"

      case Req.get(url, receive_timeout: 10_000) do
        {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
          results = parse_duckduckgo_response(body, max_results)
          {:ok, results}

        {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
          case Jason.decode(body) do
            {:ok, data} ->
              results = parse_duckduckgo_response(data, max_results)
              {:ok, results}

            {:error, _} ->
              {:error, :invalid_response}
          end

        {:ok, %Req.Response{status: status}} ->
          {:error, "Search API returned #{status}"}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp parse_duckduckgo_response(data, max_results) do
      results = []

      # Add abstract if present
      results =
        if data["Abstract"] && data["Abstract"] != "" do
          [
            %{
              title: data["Heading"] || "Result",
              url: data["AbstractURL"] || "",
              snippet: data["Abstract"]
            }
            | results
          ]
        else
          results
        end

      # Add related topics
      related = Map.get(data, "RelatedTopics", [])

      related_results =
        related
        |> Enum.filter(fn item -> is_map(item) and Map.has_key?(item, "Text") end)
        |> Enum.take(max_results - length(results))
        |> Enum.map(fn topic ->
          %{
            title: Map.get(topic, "Text", "") |> String.slice(0, 100),
            url: Map.get(topic, "FirstURL", ""),
            snippet: Map.get(topic, "Text", "")
          }
        end)

      (results ++ related_results) |> Enum.take(max_results)
    end
  end
end
