defmodule ExSolana.RPC.Request.Helpers do
  @moduledoc """
  Helper functions for creating Solana JSON-RPC API requests.
  """
  require Logger

  @commitment_options [
    commitment: [type: {:in, ["confirmed", "finalized", "processed"]}, default: "confirmed"]
  ]
  def commitment_option, do: @commitment_options

  @encoding_options [
    encoding: [type: {:in, ["base64", "base58", "json", "jsonParsed"]}, default: "base64"]
  ]
  def encoding_option, do: @encoding_options

  @with_context_option [
    with_context: [type: :boolean, default: false]
  ]
  def with_context_option, do: @with_context_option

  @data_slice_options [
    data_slice: [
      type: :map,
      keys: [
        length: [type: :non_neg_integer],
        offset: [type: :non_neg_integer]
      ]
    ]
  ]
  def data_slice_option, do: @data_slice_options

  def min_context_slot_option do
    [min_context_slot: [type: :non_neg_integer]]
  end

  @filters_option [filters: [type: {:list, :any}]]
  def filters_option, do: @filters_option

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

  @doc """
  Validates options against a schema using NimbleOptions.
  """
  @spec validate(Keyword.t(), Keyword.t()) :: {:ok, Keyword.t()} | {:error, String.t()}
  def validate(opts, schema) do
    filtered_opts = Keyword.take(opts, Keyword.keys(schema))

    case NimbleOptions.validate(filtered_opts, schema) do
      {:ok, validated} ->
        {:ok, validated}

      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error, Exception.message(error)}
    end
  rescue
    e in NimbleOptions.ValidationError ->
      {:error, Exception.message(e)}
  end

  @doc """
  Encodes a key to its base58 representation.
  """
  @spec encode_key(ExSolana.key() | String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def encode_key(key) when is_binary(key) do
    case byte_size(key) do
      32 ->
        {:ok, B58.encode58(key)}

      _ ->
        case B58.decode58(key) do
          # It's already a valid base58 string
          {:ok, _decoded} -> {:ok, key}
          _ -> {:error, "Invalid key: not a 32-byte binary or valid base58 string"}
        end
    end
  end

  def encode_key(key) do
    case ExSolana.Key.check(key) do
      :ok -> {:ok, B58.encode58(key)}
      {:ok, validated_key} -> {:ok, B58.encode58(validated_key)}
      {:error, reason} -> {:error, "Invalid key: #{reason}"}
    end
  rescue
    e in ArgumentError -> {:error, Exception.message(e)}
  end

  @doc """
  Encodes a signature to its base58 representation.
  """
  @spec encode_signature(ExSolana.Signature.t() | String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def encode_signature(signature) when is_binary(signature) do
    case byte_size(signature) do
      64 ->
        {:ok, B58.encode58(signature)}

      _ ->
        case B58.decode58(signature) do
          # It's already a valid base58 string
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
      :ok -> {:ok, B58.encode58(signature)}
      {:ok, validated_signature} -> {:ok, B58.encode58(validated_signature)}
      {:error, reason} -> {:error, "Invalid signature: #{reason}"}
    end
  rescue
    e in ArgumentError -> {:error, Exception.message(e)}
  end

  @doc """
  Encodes options for RPC requests.
  """
  @spec encode_opts(Keyword.t() | map() | list({String.t(), term()}), map() | Keyword.t()) ::
          map()
  def encode_opts(opts, defaults \\ %{}) do
    opts
    |> to_keyword_list()
    |> Keyword.merge(to_keyword_list(defaults))
    |> Map.new(fn {k, v} -> {camelize(to_string(k)), encode_value(v)} end)
  end

  @doc """
  Converts various data structures to a keyword list.
  """
  @spec to_keyword_list(Keyword.t() | map() | list({String.t(), term()})) :: Keyword.t()
  def to_keyword_list(data) do
    cond do
      Keyword.keyword?(data) -> data
      is_list(data) -> Enum.map(data, fn {k, v} -> {String.to_atom(to_string(k)), v} end)
      is_map(data) -> Enum.map(data, fn {k, v} -> {String.to_atom(to_string(k)), v} end)
    end
  end

  @doc """
  Converts a string to camelCase.
  """
  @spec camelize(String.t()) :: String.t()
  def camelize(word) do
    word
    |> String.split(~r/(?:^|[-_])|(?=[A-Z])/)
    |> Enum.reject(&(&1 == ""))
    |> camelize_list()
    |> Enum.join()
  end

  # Private functions

  defp camelize_list([h | t]) do
    [String.downcase(h) | Enum.map(t, &String.capitalize/1)]
  end

  defp encode_value(v) when is_map(v) do
    Map.new(v, fn {k, v} -> {camelize(to_string(k)), encode_value(v)} end)
  end

  defp encode_value(v) do
    cond do
      match?({:ok, _}, ExSolana.Key.check(v)) -> B58.encode58(v)
      match?({:ok, _}, ExSolana.Transaction.check(v)) -> B58.encode58(v)
      true -> v
    end
  end

  def sanitize_params(params) when is_list(params) do
    Enum.reject(params, fn
      map when is_map(map) -> map_size(map) == 0
      list when is_list(list) -> length(list) == 0
      nil -> true
      _ -> false
    end)
  end

  def sanitize_params(params) when is_tuple(params) do
    params
    |> Tuple.to_list()
    |> sanitize_params()
  end

  def sanitize_params(param), do: param

  def decode_if_base58(value) do
    case check_encoding(value) do
      {:ok, :string} ->
        try do
          {:ok, B58.decode58!(value)}
        rescue
          e in ArgumentError ->
            Logger.warning("Failed to decode base58 string: #{inspect(e)}")
            {:ok, value}
        end

      _ ->
        {:ok, value}
    end
  end

  def check_encoding(data) do
    cond do
      not is_binary(data) -> {:ok, :not_binary}
      String.valid?(data) -> {:ok, :string}
      true -> {:ok, :binary}
    end
  end
end
