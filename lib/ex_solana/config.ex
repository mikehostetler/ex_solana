defmodule ExSolana.Config do
  @moduledoc """
  Configuration module for ExSolana.

  This module provides a centralized place to access all configuration options
  for the ExSolana library.

  ## Configuration

  You can configure ExSolana by adding the following to your `config/config.exs`:

      config :ex_solana,
        rpc: [
          base_url: "https://api.mainnet-beta.solana.com",
          api_key: System.get_env("SOLANA_API_KEY")
        ],
        websocket: [
          url: "wss://api.mainnet-beta.solana.com",
          reconnect_interval: 5000
        ]

  """

  @type config_key :: atom() | {atom(), atom()}

  # Default network URLs
  @mainnet_url "https://api.mainnet-beta.solana.com"
  @devnet_url "https://api.devnet.solana.com"
  @testnet_url "https://api.testnet.solana.com"
  @localhost_url "http://localhost:8899"

  @default_websocket_url "wss://api.mainnet-beta.solana.com"

  @doc """
  Retrieves a configuration value for the given key or nested keys.

  ## Parameters

    * `key` - The configuration key to retrieve (atom or {parent, child} tuple)

  ## Returns

    The value associated with the key, or the default value if not set.

  ## Examples

      iex> ExSolana.Config.get(:verbose)
      false

      iex> ExSolana.Config.get({:rpc, :base_url})
      "https://api.mainnet-beta.solana.com"

  """
  @spec get(config_key()) :: any()
  def get(key) when is_atom(key) do
    Application.get_env(:ex_solana, key, default(key))
  end

  def get({parent, key}) when is_atom(parent) and is_atom(key) do
    :ex_solana
    |> Application.get_env(parent, [])
    |> Keyword.get(key, default({parent, key}))
  end

  @doc """
  Sets a configuration value.

  ## Parameters

    * `key` - The configuration key (atom or {parent, child} tuple)
    * `value` - The value to set

  ## Examples

      ExSolana.Config.put({:rpc, :base_url}, "https://custom-rpc.com")

  """
  @spec put(config_key(), any()) :: :ok
  def put(key, value) when is_atom(key) do
    Application.put_env(:ex_solana, key, value)
  end

  def put({parent, key}, value) when is_atom(parent) and is_atom(key) do
    current = Application.get_env(:ex_solana, parent, [])
    updated = Keyword.put(current, key, value)
    Application.put_env(:ex_solana, parent, updated)
  end

  @doc """
  Returns the default value for a given configuration key.

  ## Parameters

    * `key` - The configuration key (atom or {parent, child} tuple)

  ## Returns

    The default value for the given key.

  """
  @spec default(config_key()) :: any()
  def default(:verbose), do: false
  def default({:rpc, :base_url}), do: @mainnet_url
  def default({:rpc, :api_key}), do: nil
  def default({:websocket, :url}), do: @default_websocket_url
  def default({:websocket, :reconnect_interval}), do: 5000
  def default({:geyser, :url}), do: nil
  def default({:geyser, :token}), do: nil
  def default({:cache, :enabled}), do: false
  def default({:cache, :directory}), do: "priv/rpc_cache"
  def default({:default, :commitment}), do: "confirmed"
  def default({:default, :encoding}), do: "jsonParsed"
  def default(_), do: nil

  @doc """
  Returns the RPC URL for the given network.

  ## Parameters

    * `network` - The network atom (:mainnet_beta, :devnet, :testnet, :localhost)

  ## Returns

    The RPC URL for the network.

  ## Examples

      iex> ExSolana.Config.network_url(:mainnet_beta)
      "https://api.mainnet-beta.solana.com"

      iex> ExSolana.Config.network_url(:devnet)
      "https://api.devnet.solana.com"

  """
  @spec network_url(:mainnet_beta | :devnet | :testnet | :localhost) :: String.t()
  def network_url(:mainnet_beta), do: @mainnet_url
  def network_url(:devnet), do: @devnet_url
  def network_url(:testnet), do: @testnet_url
  def network_url(:localhost), do: @localhost_url

  @doc """
  Returns a map of all configuration options with their current values.

  ## Examples

      iex> ExSolana.Config.all()
      %{
        rpc: %{base_url: "https://api.mainnet-beta.solana.com"},
        websocket: %{url: "wss://api.mainnet-beta.solana.com"},
        # ...
      }

  """
  @spec all() :: map()
  def all do
    %{
      rpc: get_section(:rpc),
      websocket: get_section(:websocket),
      geyser: get_section(:geyser),
      cache: get_section(:cache),
      default: get_section(:default),
      verbose: get(:verbose)
    }
  end

  @doc """
  Validates the current configuration.

  ## Returns

    * `:ok` - If the configuration is valid
    * `{:error, String.t()}` - Error reason if configuration is invalid

  ## Examples

      iex> ExSolana.Config.validate()
      :ok

  """
  @spec validate() :: :ok | {:error, String.t()}
  def validate do
    with :ok <- validate_url({:rpc, :base_url}),
         :ok <- validate_url({:websocket, :url}),
         :ok <- validate_url({:geyser, :url}),
         :ok <- validate_commitment(),
         :ok <- validate_encoding() do
      :ok
    end
  end

  # Private helpers

  defp get_section(section) do
    :ex_solana
    |> Application.get_env(section, [])
    |> Map.new(fn {k, v} -> {k, v || default({section, k})} end)
  end

  defp validate_url(key) do
    url = get(key)

    if is_nil(url) or (is_binary(url) and String.starts_with?(url, ["http://", "https://", "ws://", "wss://"])) do
      :ok
    else
      {:error, "Invalid #{inspect(key)}: #{inspect(url)}"}
    end
  end

  defp validate_commitment do
    commitment = get({:default, :commitment})

    if commitment in ["processed", "confirmed", "finalized"] do
      :ok
    else
      {:error, "Invalid commitment: #{commitment}"}
    end
  end

  defp validate_encoding do
    encoding = get({:default, :encoding})

    if encoding in ["base58", "base64", "jsonParsed"] do
      :ok
    else
      {:error, "Invalid encoding: #{encoding}"}
    end
  end
end
