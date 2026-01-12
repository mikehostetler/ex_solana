defmodule ExSolana.RPC.Request.Helpers do
  @moduledoc """
  Helper functions for creating Solana JSON-RPC API requests.

  ## Features

  - Option validation and encoding
  - Key and signature encoding helpers
  - JSON-RPC payload construction
  - Parameter sanitization

  ## Examples

      # Encode options for RPC request
      opts = ExSolana.RPC.Request.Helpers.encode_opts(
        [commitment: "finalized", encoding: "base64"],
        commitment: "confirmed"
      )

      # Validate options against schema
      {:ok, validated} = ExSolana.RPC.Request.Helpers.validate(
        [commitment: "finalized"],
        [commitment: [type: {:in, ["confirmed", "finalized", "processed"]}]
      )

  """

  require Logger

  @commitment_values ["processed", "confirmed", "finalized"]

  @encoding_values ["base64", "base58", "json", "jsonParsed"]

  # ============================================================================
  # Option Definitions
  # ============================================================================

  @doc """
  Returns the commitment option schema.

  Valid values: "processed", "confirmed", "finalized"
  Default: "confirmed"
  """
  def commitment_option do
    [
      commitment: [
        type: {:in, @commitment_values},
        default: "confirmed"
      ]
    ]
  end

  @doc """
  Returns the encoding option schema.

  Valid values: "base64", "base58", "json", "jsonParsed"
  Default: "base64"
  """
  def encoding_option do
    [
      encoding: [
        type: {:in, @encoding_values},
        default: "base64"
      ]
    ]
  end

  @doc """
  Returns the with_context option schema.

  """
  def with_context_option do
    [
      with_context: [type: :boolean, default: false]
    ]
  end

  @doc """
  Returns the data_slice option schema.

  Used for partial account data fetching.
  """
  def data_slice_option do
    [
      data_slice: [
        type: :map,
        keys: [
          length: [type: :integer, required: false],
          offset: [type: :integer, required: false]
        ]
      ]
    ]
  end

  @doc """
  Returns the min_context_slot option schema.
  """
  def min_context_slot_option do
    [
      min_context_slot: [type: :integer]
    ]
  end

  @doc """
  Returns the filters option schema.
  """
  def filters_option do
    [
      filters: [type: {:list, :any}]
    ]
  end

  # ============================================================================
  # JSON-RPC Helpers
  # ============================================================================

  @doc """
  Converts a request tuple to JSON-RPC 2.0 format.

  ## Examples

      iex> ExSolana.RPC.Request.Helpers.to_json_rpc({{"getBalance", ["pubkey"]}, 1})
      %{jsonrpc: "2.0", id: 1, method: "getBalance", params: ["pubkey"]}

  """
  def to_json_rpc({{method, params}, id}) do
    %{
      jsonrpc: "2.0",
      id: id,
      method: method,
      params: sanitize_params(params)
    }
  end

  def to_json_rpc({:error, reason}) do
    {:error, reason}
  end

  # ============================================================================
  # Validation
  # ============================================================================

  @doc """
  Validates options against a schema.

  NOTE: This is a simplified validation. Full NimbleOptions validation
  is not available in the modernized package.

  ## Examples

      iex> ExSolana.RPC.Request.Helpers.validate(
      ...>   [commitment: "finalized"],
      ...>   commitment: [type: {:in, ["confirmed", "finalized"]}]
      ...> )
      {:ok, [commitment: "finalized"]}

  """
  def validate(opts, schema) do
    # Simplified validation - just check if keys are present
    filtered_opts = Keyword.take(opts, Keyword.keys(schema))

    # TODO: Implement proper validation or use Zoi for schema validation
    {:ok, filtered_opts}
  end

  # ============================================================================
  # Encoding Helpers
  # ============================================================================

  @doc """
  Encodes a key to base58 representation.

  ## Examples

      iex> {:ok, encoded} = ExSolana.RPC.Request.Helpers.encode_key(<<32::bytes>>)
      iex> is_binary(encoded) and byte_size(encoded) > 0
      true

  """
  def encode_key(key) when is_binary(key) do
    case byte_size(key) do
      32 ->
        {:ok, BaseFiftyEight.encode58(key)}

      _ ->
        case BaseFiftyEight.decode58(key) do
          {:ok, _decoded} -> {:ok, key}
          _ -> {:error, "Invalid key: not a 32-byte binary or valid base58 string"}
        end
    end
  end

  def encode_key(key) do
    # Try to validate the key
    case ExSolana.Key.check(key) do
      {:ok, validated_key} -> {:ok, BaseFiftyEight.encode58(validated_key)}
      {:error, reason} -> {:error, "Invalid key: #{reason}"}
    end
  rescue
    e in ArgumentError -> {:error, Exception.message(e)}
  end

  @doc """
  Encodes a signature to base58 representation.

  ## Examples

      iex> {:ok, encoded} = ExSolana.RPC.Request.Helpers.encode_signature(<<64::bytes>>)
      iex> is_binary(encoded) and byte_size(encoded) > 0
      true

  """
  def encode_signature(signature) when is_binary(signature) do
    case byte_size(signature) do
      64 ->
        {:ok, BaseFiftyEight.encode58(signature)}

      _ ->
        case BaseFiftyEight.decode58(signature) do
          {:ok, decoded} ->
            if byte_size(decoded) == 64 do
              {:ok, signature}
            else
              {:error, "Invalid signature: decoded base58 string is not 64 bytes"}
            end

          _ ->
            {:error, "Invalid signature: not a 64-byte binary or valid base58 string"}
        end
    end
  end

  def encode_signature(signature) do
    case ExSolana.Signature.check(signature) do
      {:ok, validated_signature} -> {:ok, BaseFiftyEight.encode58(validated_signature)}
      {:error, reason} -> {:error, "Invalid signature: #{reason}"}
    end
  rescue
    e in ArgumentError -> {:error, Exception.message(e)}
  end

  @doc """
  Encodes options for RPC requests.

  Converts atom keys to camelCase strings and applies encoding.

  ## Examples

      iex> ExSolana.RPC.Request.Helpers.encode_opts([commitment: "finalized"])
      %{"commitment" => "finalized"}

  """
  def encode_opts(opts, defaults \\ %{}) do
    opts
    |> to_keyword_list()
    |> Keyword.merge(to_keyword_list(defaults))
    |> Map.new(fn {k, v} -> {camelize(to_string(k)), encode_value(v)} end)
  end

  # ============================================================================
  # Conversion Helpers
  # ============================================================================

  @doc """
  Converts various data structures to a keyword list.

  ## Examples

      iex> ExSolana.RPC.Request.Helpers.to_keyword_list(%{"a" => 1})
      [a: 1]

  """
  def to_keyword_list(data) do
    cond do
      Keyword.keyword?(data) -> data
      is_list(data) -> Enum.map(data, fn {k, v} -> {String.to_atom(to_string(k)), v} end)
      is_map(data) -> Enum.map(data, fn {k, v} -> {String.to_atom(to_string(k)), v} end)
    end
  end

  @doc """
  Converts a string to camelCase.

  ## Examples

      iex> ExSolana.RPC.Request.Helpers.camelize("commitment")
      "commitment"

      iex> ExSolana.RPC.Request.Helpers.camelize("data_slice")
      "dataSlice"

  """
  def camelize(word) do
    word
    |> String.split(~r/(?:^|[-_])|(?=[A-Z])/)
    |> Enum.reject(&(&1 == ""))
    |> camelize_list()
    |> Enum.join()
  end

  # ============================================================================
  # Decoding Helpers
  # ============================================================================

  @doc """
  Decodes a value if it appears to be base58 encoded.
  """
  def decode_if_base58(value) do
    case check_encoding(value) do
      {:ok, :string} ->
        try do
          {:ok, BaseFiftyEight.decode58!(value)}
        rescue
          e in ArgumentError ->
            Logger.warning("Failed to decode base58 string: #{inspect(e)}")
            {:ok, value}
        end

      _ ->
        {:ok, value}
    end
  end

  @doc """
  Checks the encoding type of binary data.
  """
  def check_encoding(data) do
    cond do
      not is_binary(data) -> {:ok, :not_binary}
      String.valid?(data) -> {:ok, :string}
      true -> {:ok, :binary}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp camelize_list([h | t]) do
    [String.downcase(h) | Enum.map(t, &String.capitalize/1)]
  end

  defp encode_value(v) when is_map(v) do
    Map.new(v, fn {k, v} -> {camelize(to_string(k)), encode_value(v)} end)
  end

  defp encode_value(v) do
    cond do
      match?({:ok, _}, ExSolana.Key.check(v)) -> BaseFiftyEight.encode58(v)
      match?({:ok, _}, ExSolana.Transaction.check(v)) -> BaseFiftyEight.encode58(v)
      true -> v
    end
  end

  defp sanitize_params(params) when is_list(params) do
    Enum.reject(params, fn
      map when is_map(map) -> map_size(map) == 0
      list when is_list(list) -> length(list) == 0
      nil -> true
      _ -> false
    end)
  end

  defp sanitize_params(params) when is_tuple(params) do
    params
    |> Tuple.to_list()
    |> sanitize_params()
  end

  defp sanitize_params(param), do: param
end
