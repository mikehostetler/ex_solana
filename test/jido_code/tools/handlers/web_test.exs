defmodule JidoCode.Tools.Handlers.WebTest do
  use ExUnit.Case, async: false

  alias JidoCode.Tools.Handlers.Web.{Fetch, Search}
  alias JidoCode.Tools.Security.Web, as: WebSecurity

  describe "WebSecurity.validate_url/2" do
    test "allows URL in default allowlist" do
      assert {:ok, _} = WebSecurity.validate_url("https://hexdocs.pm/elixir")
      assert {:ok, _} = WebSecurity.validate_url("https://elixir-lang.org/docs")
      assert {:ok, _} = WebSecurity.validate_url("https://github.com/elixir-lang/elixir")
    end

    test "allows subdomain of allowed domain" do
      assert {:ok, _} = WebSecurity.validate_url("https://api.github.com/repos")
      assert {:ok, _} = WebSecurity.validate_url("https://www.erlang.org/docs")
    end

    test "rejects domain not in allowlist" do
      assert {:error, :domain_not_allowed} = WebSecurity.validate_url("https://evil.com/hack")
      assert {:error, :domain_not_allowed} = WebSecurity.validate_url("https://example.com")
    end

    test "rejects blocked schemes" do
      assert {:error, :blocked_scheme} = WebSecurity.validate_url("file:///etc/passwd")
      assert {:error, :blocked_scheme} = WebSecurity.validate_url("javascript:alert(1)")
      assert {:error, :blocked_scheme} = WebSecurity.validate_url("data:text/html,<script>")
    end

    test "allows custom allowlist" do
      opts = [allowed_domains: ["example.com", "test.org"]]
      assert {:ok, _} = WebSecurity.validate_url("https://example.com/page", opts)
      assert {:ok, _} = WebSecurity.validate_url("https://sub.test.org/page", opts)
      assert {:error, :domain_not_allowed} = WebSecurity.validate_url("https://hexdocs.pm", opts)
    end

    test "rejects invalid URLs" do
      assert {:error, :missing_scheme} = WebSecurity.validate_url("hexdocs.pm/elixir")
      # Empty host is treated as missing host
      assert {:error, :missing_host} = WebSecurity.validate_url("https:///path")
    end
  end

  describe "WebSecurity.allowed_content_type?/1" do
    test "allows text/html" do
      assert WebSecurity.allowed_content_type?("text/html")
      assert WebSecurity.allowed_content_type?("text/html; charset=utf-8")
    end

    test "allows application/json" do
      assert WebSecurity.allowed_content_type?("application/json")
    end

    test "allows text/plain" do
      assert WebSecurity.allowed_content_type?("text/plain")
    end

    test "rejects binary content types" do
      refute WebSecurity.allowed_content_type?("application/octet-stream")
      refute WebSecurity.allowed_content_type?("image/png")
      refute WebSecurity.allowed_content_type?("application/pdf")
    end
  end

  describe "Fetch.html_to_markdown/1" do
    test "converts headings" do
      html = "<h1>Title</h1><h2>Subtitle</h2>"
      result = Fetch.html_to_markdown(html)

      assert result =~ "# Title"
      assert result =~ "## Subtitle"
    end

    test "converts paragraphs" do
      html = "<p>First paragraph.</p><p>Second paragraph.</p>"
      result = Fetch.html_to_markdown(html)

      assert result =~ "First paragraph"
      assert result =~ "Second paragraph"
    end

    test "converts lists" do
      html = "<ul><li>Item 1</li><li>Item 2</li></ul>"
      result = Fetch.html_to_markdown(html)

      assert result =~ "- Item 1"
      assert result =~ "- Item 2"
    end

    test "converts code blocks" do
      html = "<pre><code>defmodule Test do\nend</code></pre>"
      result = Fetch.html_to_markdown(html)

      assert result =~ "```"
      assert result =~ "defmodule Test"
    end

    test "converts inline formatting" do
      html = "<p>This is <strong>bold</strong> and <em>italic</em>.</p>"
      result = Fetch.html_to_markdown(html)

      assert result =~ "**bold**"
      assert result =~ "*italic*"
    end

    test "removes script and style tags" do
      html = "<script>alert('xss')</script><style>.bad{}</style><p>Content</p>"
      result = Fetch.html_to_markdown(html)

      refute result =~ "alert"
      refute result =~ ".bad"
      assert result =~ "Content"
    end

    test "handles malformed HTML gracefully" do
      html = "<p>Unclosed <b>tags"
      result = Fetch.html_to_markdown(html)

      assert is_binary(result)
      assert result =~ "Unclosed"
    end
  end

  describe "Fetch.execute/2 with Bypass" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass}
    end

    test "fetches HTML content successfully", %{bypass: bypass} do
      html = """
      <!DOCTYPE html>
      <html>
      <head><title>Test Page</title></head>
      <body><h1>Hello World</h1><p>Content here.</p></body>
      </html>
      """

      Bypass.expect_once(bypass, "GET", "/page", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/html; charset=utf-8")
        |> Plug.Conn.resp(200, html)
      end)

      url = "http://localhost:#{bypass.port}/page"
      context = %{allowed_domains: ["localhost"]}

      assert {:ok, result} = Fetch.execute(%{"url" => url}, context)
      parsed = Jason.decode!(result)

      assert parsed["title"] == "Test Page"
      assert parsed["content"] =~ "Hello World"
    end

    test "handles JSON response", %{bypass: bypass} do
      json = Jason.encode!(%{"message" => "Hello", "count" => 42})

      Bypass.expect_once(bypass, "GET", "/api", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, json)
      end)

      url = "http://localhost:#{bypass.port}/api"
      context = %{allowed_domains: ["localhost"]}

      assert {:ok, result} = Fetch.execute(%{"url" => url}, context)
      parsed = Jason.decode!(result)

      assert parsed["content"] =~ "message"
    end

    test "returns error for disallowed domain", %{bypass: _bypass} do
      context = %{allowed_domains: ["hexdocs.pm"]}

      assert {:error, error} = Fetch.execute(%{"url" => "https://evil.com"}, context)
      assert error =~ "not in allowlist" or error =~ "not allowed"
    end

    test "returns error for 404", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/missing", fn conn ->
        Plug.Conn.resp(conn, 404, "Not Found")
      end)

      url = "http://localhost:#{bypass.port}/missing"
      context = %{allowed_domains: ["localhost"]}

      assert {:error, error} = Fetch.execute(%{"url" => url}, context)
      assert error =~ "404"
    end

    test "returns error for invalid content type", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/binary", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/octet-stream")
        |> Plug.Conn.resp(200, <<0, 1, 2, 3>>)
      end)

      url = "http://localhost:#{bypass.port}/binary"
      context = %{allowed_domains: ["localhost"]}

      assert {:error, error} = Fetch.execute(%{"url" => url}, context)
      assert error =~ "not allowed"
    end

    test "returns error for missing url argument", %{bypass: _bypass} do
      assert {:error, error} = Fetch.execute(%{}, %{})
      assert error =~ "requires a url"
    end
  end

  describe "Search.execute/2" do
    # Note: These tests use the actual DuckDuckGo API
    # For CI/offline testing, you'd want to mock this with Bypass
    @tag :external_api
    test "searches and returns results" do
      result = Search.execute(%{"query" => "Elixir programming language"}, %{})

      # DuckDuckGo Instant Answer API may not always return results
      # So we just verify the format is correct
      case result do
        {:ok, json} ->
          parsed = Jason.decode!(json)
          assert is_map(parsed)
          assert is_list(parsed["results"])

        {:error, _} ->
          # API might be unavailable, that's ok for tests
          :ok
      end
    end

    test "returns error for missing query" do
      assert {:error, error} = Search.execute(%{}, %{})
      assert error =~ "requires a query"
    end

    test "limits results to max 20" do
      # This just verifies the limit is applied, actual results depend on API
      result = Search.execute(%{"query" => "test", "num_results" => 100}, %{})

      case result do
        {:ok, json} ->
          parsed = Jason.decode!(json)
          assert length(parsed["results"]) <= 20

        {:error, _} ->
          :ok
      end
    end
  end

  # ============================================================================
  # Session Context Tests
  # ============================================================================

  describe "session-aware context" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass}
    end

    test "Fetch includes session_id in result when provided", %{bypass: bypass} do
      html = "<html><head><title>Test</title></head><body>Content</body></html>"

      Bypass.expect_once(bypass, "GET", "/page", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/html")
        |> Plug.Conn.resp(200, html)
      end)

      url = "http://localhost:#{bypass.port}/page"
      session_id = "550e8400-e29b-41d4-a716-446655440000"
      context = %{allowed_domains: ["localhost"], session_id: session_id}

      assert {:ok, result} = Fetch.execute(%{"url" => url}, context)
      parsed = Jason.decode!(result)

      assert parsed["session_id"] == session_id
      assert parsed["title"] == "Test"
    end

    test "Fetch works without session_id (backwards compatibility)", %{bypass: bypass} do
      html = "<html><head><title>Test</title></head><body>Content</body></html>"

      Bypass.expect_once(bypass, "GET", "/page", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/html")
        |> Plug.Conn.resp(200, html)
      end)

      url = "http://localhost:#{bypass.port}/page"
      context = %{allowed_domains: ["localhost"]}

      assert {:ok, result} = Fetch.execute(%{"url" => url}, context)
      parsed = Jason.decode!(result)

      refute Map.has_key?(parsed, "session_id")
      assert parsed["title"] == "Test"
    end

    @tag :external_api
    test "Search includes session_id in result when provided" do
      session_id = "550e8400-e29b-41d4-a716-446655440000"
      context = %{session_id: session_id}

      result = Search.execute(%{"query" => "test"}, context)

      case result do
        {:ok, json} ->
          parsed = Jason.decode!(json)
          assert parsed["session_id"] == session_id
          assert is_list(parsed["results"])

        {:error, _} ->
          # API might be unavailable
          :ok
      end
    end

    @tag :external_api
    test "Search works without session_id (backwards compatibility)" do
      context = %{}

      result = Search.execute(%{"query" => "test"}, context)

      case result do
        {:ok, json} ->
          parsed = Jason.decode!(json)
          refute Map.has_key?(parsed, "session_id")
          assert is_list(parsed["results"])

        {:error, _} ->
          # API might be unavailable
          :ok
      end
    end
  end
end
