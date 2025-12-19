defmodule JidoCode.Tools.DisplayTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Display
  alias JidoCode.Tools.Result

  describe "format_tool_call/3" do
    test "formats a simple tool call with one parameter" do
      result = Display.format_tool_call("read_file", %{"path" => "src/main.ex"}, "call_123")
      assert result == "⚙ read_file(path: \"src/main.ex\")"
    end

    test "formats a tool call with multiple parameters" do
      params = %{"pattern" => "TODO", "path" => "lib", "recursive" => true}
      result = Display.format_tool_call("grep", params, "call_456")
      # Parameters are sorted alphabetically
      assert result == "⚙ grep(path: \"lib\", pattern: \"TODO\", recursive: true)"
    end

    test "formats a tool call with no parameters" do
      result = Display.format_tool_call("list_tools", %{}, "call_789")
      assert result == "⚙ list_tools()"
    end

    test "formats a tool call with array parameter" do
      params = %{"command" => "mix", "args" => ["test", "--trace"]}
      result = Display.format_tool_call("run_command", params, "call_abc")
      assert result =~ "⚙ run_command("
      assert result =~ "command: \"mix\""
      assert result =~ "args: [\"test\", \"--trace\"]"
    end

    test "truncates long parameter values" do
      long_value = String.duplicate("a", 200)
      params = %{"content" => long_value}
      result = Display.format_tool_call("write_file", params, "call_def")
      assert String.length(result) < 200
      assert result =~ "[...]"
    end
  end

  describe "format_params/1" do
    test "returns empty string for empty map" do
      assert Display.format_params(%{}) == ""
    end

    test "formats single parameter" do
      assert Display.format_params(%{"path" => "file.ex"}) == "path: \"file.ex\""
    end

    test "formats multiple parameters in sorted order" do
      params = %{"z_param" => "z", "a_param" => "a"}
      result = Display.format_params(params)
      assert result == "a_param: \"a\", z_param: \"z\""
    end

    test "formats integer values" do
      assert Display.format_params(%{"timeout" => 5000}) == "timeout: 5000"
    end

    test "formats boolean values" do
      assert Display.format_params(%{"recursive" => true}) == "recursive: true"
      assert Display.format_params(%{"recursive" => false}) == "recursive: false"
    end

    test "formats list values with items" do
      params = %{"args" => ["a", "b", "c"]}
      result = Display.format_params(params)
      assert result == "args: [\"a\", \"b\", \"c\"]"
    end

    test "truncates long lists" do
      params = %{"items" => ["a", "b", "c", "d", "e", "f", "g"]}
      result = Display.format_params(params)
      assert result =~ "..."
    end

    test "formats nested maps as {...}" do
      params = %{"config" => %{"nested" => "value"}}
      result = Display.format_params(params)
      assert result == "config: {...}"
    end
  end

  describe "format_tool_result/1" do
    test "formats successful result" do
      result = %Result{
        tool_call_id: "call_123",
        tool_name: "read_file",
        status: :ok,
        content: "defmodule Main do",
        duration_ms: 45
      }

      formatted = Display.format_tool_result(result)
      assert formatted == "✓ read_file [45ms]: defmodule Main do"
    end

    test "formats error result" do
      result = %Result{
        tool_call_id: "call_123",
        tool_name: "read_file",
        status: :error,
        content: "File not found: src/missing.ex",
        duration_ms: 12
      }

      formatted = Display.format_tool_result(result)
      assert formatted == "✗ read_file [12ms]: File not found: src/missing.ex"
    end

    test "formats timeout result" do
      result = %Result{
        tool_call_id: "call_123",
        tool_name: "slow_operation",
        status: :timeout,
        content: "Tool execution timed out after 30_000ms",
        duration_ms: 30_000
      }

      formatted = Display.format_tool_result(result)
      assert formatted == "⏱ slow_operation [30000ms]: Tool execution timed out after 30_000ms"
    end

    test "truncates long content in result" do
      long_content = String.duplicate("x", 600)

      result = %Result{
        tool_call_id: "call_123",
        tool_name: "read_file",
        status: :ok,
        content: long_content,
        duration_ms: 100
      }

      formatted = Display.format_tool_result(result)
      assert String.length(formatted) < 600
      assert formatted =~ "[...]"
    end
  end

  describe "truncate_content/2" do
    test "returns short content unchanged" do
      assert Display.truncate_content("short") == "short"
    end

    test "truncates long content with suffix" do
      long = String.duplicate("a", 600)
      result = Display.truncate_content(long)
      assert String.length(result) == 506
      assert String.ends_with?(result, " [...]")
    end

    test "uses custom max length" do
      result = Display.truncate_content("hello world", 5)
      assert result == "hello [...]"
    end

    test "normalizes newlines to spaces" do
      content = "line1\nline2\nline3"
      result = Display.truncate_content(content)
      assert result == "line1 line2 line3"
    end

    test "normalizes multiple whitespace to single space" do
      content = "word1   word2\t\tword3"
      result = Display.truncate_content(content)
      assert result == "word1 word2 word3"
    end

    test "handles non-string content" do
      result = Display.truncate_content(123)
      assert result == "123"
    end
  end

  describe "detect_syntax/2" do
    test "detects Elixir from file extension" do
      assert Display.detect_syntax("anything", %{path: "lib/foo.ex"}) == :elixir
      assert Display.detect_syntax("anything", %{path: "test/bar_test.exs"}) == :elixir
    end

    test "detects JSON from file extension" do
      assert Display.detect_syntax("anything", %{path: "config.json"}) == :json
    end

    test "detects markdown from file extension" do
      assert Display.detect_syntax("anything", %{path: "README.md"}) == :markdown
    end

    test "detects Elixir from content pattern" do
      assert Display.detect_syntax("defmodule Foo do", %{}) == :elixir
      assert Display.detect_syntax("def foo do", %{}) == :elixir
    end

    test "detects JSON from content structure" do
      assert Display.detect_syntax(~s({"key": "value"}), %{}) == :json
      assert Display.detect_syntax("[1, 2, 3]", %{}) == :json
    end

    test "returns text for plain content" do
      assert Display.detect_syntax("plain text", %{}) == :text
    end

    test "returns unknown for non-string content" do
      assert Display.detect_syntax(123, %{}) == :unknown
    end

    test "detects various file extensions" do
      assert Display.detect_syntax("", %{path: "app.js"}) == :javascript
      assert Display.detect_syntax("", %{path: "app.ts"}) == :typescript
      assert Display.detect_syntax("", %{path: "app.py"}) == :python
      assert Display.detect_syntax("", %{path: "app.rb"}) == :ruby
      assert Display.detect_syntax("", %{path: "app.rs"}) == :rust
      assert Display.detect_syntax("", %{path: "app.go"}) == :go
      assert Display.detect_syntax("", %{path: "index.html"}) == :html
      assert Display.detect_syntax("", %{path: "styles.css"}) == :css
      assert Display.detect_syntax("", %{path: "config.yaml"}) == :yaml
      assert Display.detect_syntax("", %{path: "config.yml"}) == :yaml
      assert Display.detect_syntax("", %{path: "data.xml"}) == :xml
      assert Display.detect_syntax("", %{path: "query.sql"}) == :sql
      assert Display.detect_syntax("", %{path: "script.sh"}) == :shell
      assert Display.detect_syntax("", %{path: "module.erl"}) == :erlang
      assert Display.detect_syntax("", %{path: "header.hrl"}) == :erlang
    end
  end
end
