defmodule JidoCode.Tools.Display do
  @moduledoc """
  Formats tool calls and results for human-readable display.

  This module provides formatting functions to prepare tool call events
  for display in the TUI. It handles parameter condensation, content
  truncation, and status-appropriate formatting.

  ## Display Format

  Tool calls are formatted with a gear icon and condensed parameters:

      ⚙ read_file(path: "src/main.ex")

  Tool results are formatted with status icons and timing:

      ✓ read_file [45ms]: defmodule Main do...
      ✗ read_file [12ms]: File not found: src/missing.ex
      ⏱ slow_operation [30000ms]: Tool execution timed out

  ## Usage

      # Format a tool call
      Display.format_tool_call("read_file", %{"path" => "src/main.ex"}, "call_123")
      # => "⚙ read_file(path: \"src/main.ex\")"

      # Format a tool result
      Display.format_tool_result(result)
      # => "✓ read_file [45ms]: defmodule Main do..."
  """

  alias JidoCode.Tools.Result

  @default_max_length 500
  @truncation_suffix " [...]"

  # Status icons for display
  @icon_tool "⚙"
  @icon_ok "✓"
  @icon_error "✗"
  @icon_timeout "⏱"

  # ============================================================================
  # Tool Call Formatting
  # ============================================================================

  @doc """
  Formats a tool call for display.

  Returns a human-readable string showing the tool name and condensed parameters.

  ## Parameters

  - `tool_name` - Name of the tool being called
  - `params` - Map of parameters being passed
  - `_call_id` - Tool call ID (included for context, not displayed)

  ## Examples

      iex> Display.format_tool_call("read_file", %{"path" => "src/main.ex"}, "call_123")
      "⚙ read_file(path: \\"src/main.ex\\")"

      iex> Display.format_tool_call("grep", %{"pattern" => "TODO", "path" => "lib"}, "call_456")
      "⚙ grep(pattern: \\"TODO\\", path: \\"lib\\")"
  """
  @spec format_tool_call(String.t(), map(), String.t()) :: String.t()
  def format_tool_call(tool_name, params, _call_id) do
    formatted_params = format_params(params)
    "#{@icon_tool} #{tool_name}(#{formatted_params})"
  end

  @doc """
  Formats tool parameters for condensed display.

  Converts a parameter map to a compact string representation.
  Long values are truncated.

  ## Examples

      iex> Display.format_params(%{"path" => "src/main.ex"})
      "path: \\"src/main.ex\\""

      iex> Display.format_params(%{"command" => "mix", "args" => ["test", "--trace"]})
      "command: \\"mix\\", args: [\\"test\\", \\"trace\\"]"

      iex> Display.format_params(%{})
      ""
  """
  @spec format_params(map()) :: String.t()
  def format_params(params) when map_size(params) == 0, do: ""

  def format_params(params) when is_map(params) do
    params
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.map_join(", ", fn {key, value} -> "#{key}: #{format_value(value)}" end)
  end

  # ============================================================================
  # Tool Result Formatting
  # ============================================================================

  @doc """
  Formats a tool result for display.

  Returns a human-readable string with status icon, tool name, duration,
  and content preview.

  ## Parameters

  - `result` - A `%Result{}` struct from tool execution

  ## Examples

      iex> result = %Result{status: :ok, tool_name: "read_file", content: "defmodule Main", duration_ms: 45}
      iex> Display.format_tool_result(result)
      "✓ read_file [45ms]: defmodule Main"

      iex> result = %Result{status: :error, tool_name: "read_file", content: "File not found", duration_ms: 12}
      iex> Display.format_tool_result(result)
      "✗ read_file [12ms]: File not found"

      iex> result = %Result{status: :timeout, tool_name: "slow_op", content: "Timed out", duration_ms: 30000}
      iex> Display.format_tool_result(result)
      "⏱ slow_op [30000ms]: Timed out"
  """
  @spec format_tool_result(Result.t()) :: String.t()
  def format_tool_result(%Result{} = result) do
    icon = status_icon(result.status)
    content_preview = truncate_content(result.content)
    "#{icon} #{result.tool_name} [#{result.duration_ms}ms]: #{content_preview}"
  end

  # ============================================================================
  # Content Formatting
  # ============================================================================

  @doc """
  Truncates content to a maximum length for display.

  If content exceeds the maximum length, it is truncated and appended
  with "[...]" to indicate continuation.

  ## Parameters

  - `content` - String content to truncate
  - `max_length` - Maximum length (default: 500)

  ## Examples

      iex> Display.truncate_content("short")
      "short"

      iex> long = String.duplicate("a", 600)
      iex> Display.truncate_content(long) |> String.length()
      506

      iex> Display.truncate_content("custom", 3)
      "cus [...]"
  """
  @spec truncate_content(String.t(), non_neg_integer()) :: String.t()
  def truncate_content(content, max_length \\ @default_max_length)

  def truncate_content(content, max_length) when is_binary(content) do
    # Normalize newlines to spaces for single-line display
    normalized = String.replace(content, ~r/\s+/, " ")

    if String.length(normalized) > max_length do
      String.slice(normalized, 0, max_length) <> @truncation_suffix
    else
      normalized
    end
  end

  def truncate_content(content, max_length) do
    truncate_content(inspect(content), max_length)
  end

  @doc """
  Detects the syntax type of content for highlighting hints.

  Returns an atom indicating the likely content type based on
  file extension patterns or content inspection.

  ## Parameters

  - `content` - The content to inspect
  - `context` - Optional context map with `:path` key for file extension hint

  ## Returns

  One of: `:elixir`, `:json`, `:text`, `:unknown`

  ## Examples

      iex> Display.detect_syntax("defmodule Foo do", %{})
      :elixir

      iex> Display.detect_syntax("{\"key\": \"value\"}", %{})
      :json

      iex> Display.detect_syntax("plain text", %{path: "README.md"})
      :markdown
  """
  @spec detect_syntax(String.t(), map()) :: atom()
  def detect_syntax(content, context \\ %{})

  def detect_syntax(_content, %{path: path}) when is_binary(path) do
    extension_to_syntax(Path.extname(path))
  end

  def detect_syntax(content, _context) when is_binary(content) do
    cond do
      String.starts_with?(content, "defmodule ") or String.starts_with?(content, "def ") ->
        :elixir

      String.starts_with?(String.trim(content), "{") or
          String.starts_with?(String.trim(content), "[") ->
        case Jason.decode(content) do
          {:ok, _} -> :json
          _ -> :text
        end

      true ->
        :text
    end
  end

  def detect_syntax(_content, _context), do: :unknown

  # ============================================================================
  # Private Functions
  # ============================================================================

  @spec status_icon(Result.status()) :: String.t()
  defp status_icon(:ok), do: @icon_ok
  defp status_icon(:error), do: @icon_error
  defp status_icon(:timeout), do: @icon_timeout

  @spec format_value(term()) :: String.t()
  defp format_value(value) when is_binary(value) do
    truncated = truncate_content(value, 100)
    inspect(truncated)
  end

  defp format_value(value) when is_list(value) do
    items =
      value
      |> Enum.take(5)
      |> Enum.map_join(", ", &format_list_item/1)

    suffix = if length(value) > 5, do: ", ...", else: ""
    "[#{items}#{suffix}]"
  end

  defp format_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(value) when is_float(value), do: Float.to_string(value)
  defp format_value(value) when is_boolean(value), do: Atom.to_string(value)
  defp format_value(value) when is_atom(value), do: inspect(value)
  defp format_value(value) when is_map(value), do: "{...}"
  defp format_value(value), do: inspect(value)

  @spec format_list_item(term()) :: String.t()
  defp format_list_item(item) when is_binary(item), do: inspect(item)
  defp format_list_item(item), do: inspect(item)

  @spec extension_to_syntax(String.t()) :: atom()
  defp extension_to_syntax(".ex"), do: :elixir
  defp extension_to_syntax(".exs"), do: :elixir
  defp extension_to_syntax(".json"), do: :json
  defp extension_to_syntax(".md"), do: :markdown
  defp extension_to_syntax(".markdown"), do: :markdown
  defp extension_to_syntax(".js"), do: :javascript
  defp extension_to_syntax(".ts"), do: :typescript
  defp extension_to_syntax(".py"), do: :python
  defp extension_to_syntax(".rb"), do: :ruby
  defp extension_to_syntax(".rs"), do: :rust
  defp extension_to_syntax(".go"), do: :go
  defp extension_to_syntax(".html"), do: :html
  defp extension_to_syntax(".css"), do: :css
  defp extension_to_syntax(".yaml"), do: :yaml
  defp extension_to_syntax(".yml"), do: :yaml
  defp extension_to_syntax(".xml"), do: :xml
  defp extension_to_syntax(".sql"), do: :sql
  defp extension_to_syntax(".sh"), do: :shell
  defp extension_to_syntax(".bash"), do: :shell
  defp extension_to_syntax(".erl"), do: :erlang
  defp extension_to_syntax(".hrl"), do: :erlang
  defp extension_to_syntax(_), do: :text
end
