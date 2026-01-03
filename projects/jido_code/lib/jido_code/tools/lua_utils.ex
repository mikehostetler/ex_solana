defmodule JidoCode.Tools.LuaUtils do
  @moduledoc """
  Shared utilities for Lua/Luerl integration.

  This module provides common functions for:
  - String escaping for Lua literals
  - Lua table encoding/decoding
  - Result parsing from Luerl calls

  ## String Escaping

  Lua strings require escaping of special characters. Use `escape_string/1`
  to safely embed user input in Lua code:

      iex> LuaUtils.escape_string("hello\\nworld")
      "hello\\\\nworld"

  For complete Lua string literals (with quotes), use `encode_string/1`:

      iex> LuaUtils.encode_string("hello")
      "\"hello\""

  ## Result Parsing

  Luerl returns results in a specific format. Use the parsing helpers
  to convert to standard Elixir `{:ok, _}` / `{:error, _}` tuples:

      iex> LuaUtils.parse_lua_result({:ok, [42], state})
      {:ok, 42}

      iex> LuaUtils.parse_lua_result({:ok, [nil, "error"], state})
      {:error, "error"}
  """

  alias JidoCode.ErrorFormatter

  # ============================================================================
  # String Escaping
  # ============================================================================

  @doc """
  Escapes special characters in a string for use in Lua code.

  Handles the following escape sequences:
  - `\\` → `\\\\`
  - `"` → `\\"`
  - `\\n` → `\\\\n`
  - `\\r` → `\\\\r`
  - `\\t` → `\\\\t`

  ## Parameters

  - `str` - The string to escape

  ## Returns

  The escaped string (without surrounding quotes).

  ## Examples

      iex> LuaUtils.escape_string("hello")
      "hello"

      iex> LuaUtils.escape_string("line1\\nline2")
      "line1\\\\nline2"

      iex> LuaUtils.escape_string("say \\"hello\\"")
      "say \\\\\\"hello\\\\\\""
  """
  @spec escape_string(String.t()) :: String.t()
  def escape_string(str) when is_binary(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  @doc """
  Encodes a string as a Lua string literal with surrounding quotes.

  ## Parameters

  - `str` - The string to encode

  ## Returns

  The string as a Lua literal: `"escaped_content"`.

  ## Examples

      iex> LuaUtils.encode_string("hello")
      "\\"hello\\""

      iex> LuaUtils.encode_string("line1\\nline2")
      "\\"line1\\\\nline2\\""
  """
  @spec encode_string(String.t()) :: String.t()
  def encode_string(str) when is_binary(str) do
    "\"#{escape_string(str)}\""
  end

  # ============================================================================
  # Result Parsing
  # ============================================================================

  @doc """
  Parses a Luerl execution result into a standard Elixir result tuple.

  Handles the common patterns:
  - `{:ok, [nil, error_msg], state}` → `{:error, error_msg}`
  - `{:ok, [result], state}` → `{:ok, result}`
  - `{:ok, [], state}` → `{:ok, nil}`
  - `{:error, reason, state}` → `{:error, formatted_reason}`

  ## Parameters

  - `result` - The result tuple from `:luerl.do/2` or `:luerl.call/3`

  ## Returns

  - `{:ok, value}` - On successful execution
  - `{:error, reason}` - On failure

  ## Examples

      iex> LuaUtils.parse_lua_result({:ok, [42], state})
      {:ok, 42}

      iex> LuaUtils.parse_lua_result({:ok, [nil, "not found"], state})
      {:error, "not found"}
  """
  @spec parse_lua_result(
          {:ok, list(), term()} | {:error, term(), term()}
        ) :: {:ok, term()} | {:error, term()}
  def parse_lua_result({:ok, [nil, error_msg], _state}) when is_binary(error_msg) do
    {:error, error_msg}
  end

  def parse_lua_result({:ok, [result], _state}) do
    {:ok, result}
  end

  def parse_lua_result({:ok, [], _state}) do
    {:ok, nil}
  end

  def parse_lua_result({:ok, results, _state}) when is_list(results) do
    {:ok, results}
  end

  def parse_lua_result({:error, reason, _state}) do
    {:error, ErrorFormatter.format(reason)}
  end

  @doc """
  Parses a Luerl execution result with exception handling.

  Same as `parse_lua_result/1` but handles exceptions and catch clauses.
  Returns the new Lua state on success for state updates.

  ## Returns

  - `{:ok, value, new_state}` - On success with updated state
  - `{:error, reason}` - On failure

  ## Examples

      result = safe_lua_execute(fn ->
        :luerl.do("return 42", state)
      end)
  """
  @spec safe_lua_execute((() -> {:ok, list(), term()} | {:error, term(), term()})) ::
          {:ok, term(), term()} | {:error, term()}
  def safe_lua_execute(fun) when is_function(fun, 0) do
    case fun.() do
      {:ok, [nil, error_msg], _state} when is_binary(error_msg) ->
        {:error, error_msg}

      {:ok, [result], new_state} ->
        {:ok, result, new_state}

      {:ok, [], new_state} ->
        {:ok, nil, new_state}

      {:ok, results, new_state} when is_list(results) ->
        {:ok, results, new_state}

      {:error, reason, _state} ->
        {:error, ErrorFormatter.format(reason)}
    end
  rescue
    e ->
      {:error, Exception.message(e)}
  catch
    kind, reason ->
      {:error, "#{kind}: #{inspect(reason)}"}
  end

  # ============================================================================
  # Table Encoding
  # ============================================================================

  @doc """
  Encodes an Elixir value as a Lua literal.

  Handles:
  - Strings → quoted and escaped
  - Numbers → as-is
  - Booleans → `true` or `false`
  - nil → `nil`
  - Lists → Lua arrays `{1, 2, 3}`
  - Keyword lists → Lua tables `{key = value, ...}`

  ## Examples

      iex> LuaUtils.encode_value("hello")
      "\\"hello\\""

      iex> LuaUtils.encode_value(42)
      "42"

      iex> LuaUtils.encode_value([offset: 10, limit: 50])
      "{offset = 10, limit = 50}"
  """
  @spec encode_value(term()) :: String.t()
  def encode_value(nil), do: "nil"
  def encode_value(true), do: "true"
  def encode_value(false), do: "false"
  def encode_value(num) when is_number(num), do: to_string(num)
  def encode_value(str) when is_binary(str), do: encode_string(str)

  def encode_value(list) when is_list(list) do
    if Keyword.keyword?(list) do
      # Keyword list → Lua table with keys
      items =
        list
        |> Enum.map(fn {k, v} -> "#{k} = #{encode_value(v)}" end)
        |> Enum.join(", ")

      "{#{items}}"
    else
      # Plain list → Lua array
      items =
        list
        |> Enum.map(&encode_value/1)
        |> Enum.join(", ")

      "{#{items}}"
    end
  end

  def encode_value(map) when is_map(map) do
    items =
      map
      |> Enum.map(fn {k, v} -> "[#{encode_value(to_string(k))}] = #{encode_value(v)}" end)
      |> Enum.join(", ")

    "{#{items}}"
  end

  def encode_value(other), do: inspect(other)
end
