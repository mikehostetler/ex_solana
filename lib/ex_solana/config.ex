defmodule ExSolana.Config do
  @moduledoc """
  Configuration module for ExSolana.

  This module provides a centralized place to access all configuration options
  for the ExSolana library. It sets default values and retrieves values from
  the application environment.

  You can configure ExSolana by adding the following to your `config/config.exs`:

      config :ex_solana,
        rpc: [
          base_url: "https://mainnet.helius-rpc.com/",
          api_key: System.get_env("SOLANA_API_KEY")
        ],
        websocket: [
          url: "wss://api.mainnet-beta.solana.com",
          reconnect_interval: 5000
        ],
        # ... other options

  """

  @type config_key :: atom() | {atom(), atom()}

  @doc """
  Retrieves a configuration value for the given key or nested keys.

  ## Parameters

  - `key`: The configuration key to retrieve. Can be a single atom for top-level keys,
           or a tuple of two atoms for nested keys.

  ## Returns

  The value associated with the key, or the default value if not set.

  ## Examples

      iex> ExSolana.Config.get(:verbose)
      false

      iex> ExSolana.Config.get({:rpc, :base_url})
      "https://mainnet.helius-rpc.com/"

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
  Returns the default value for a given configuration key.

  ## Parameters

  - `key`: The configuration key. Can be a single atom for top-level keys,
           or a tuple of two atoms for nested keys.

  ## Returns

  The default value for the given key.
  """
  @spec default(config_key()) :: any()
  def default(:verbose), do: false
  def default({:rpc, :base_url}), do: "https://api.mainnet-beta.solana.com"
  def default({:rpc, :api_key}), do: nil
  def default({:websocket, :url}), do: "wss://api.mainnet-beta.solana.com"
  def default({:websocket, :reconnect_interval}), do: 5000
  def default({:geyser, :url}), do: nil
  def default({:geyser, :token}), do: nil
  def default({:cache, :enabled}), do: false
  def default({:cache, :use_json}), do: true
  def default({:cache, :directory}), do: "priv/rpc_cache"
  def default({:default, :commitment}), do: "confirmed"
  def default({:default, :encoding}), do: "jsonParsed"
  def default({:default, :transaction_details}), do: "full"
  def default({:default, :max_supported_transaction_version}), do: 0
  def default({:default, :show_rewards}), do: true
  def default(_), do: nil

  @doc """
  Returns a map of all configuration options with their current values.

  ## Returns

  A map containing all configuration options and their values.

  ## Examples

      iex> ExSolana.Config.all()
      %{
        rpc: %{
          base_url: "https://mainnet.helius-rpc.com/",
          api_key: nil
        },
        websocket: %{
          url: "wss://api.mainnet-beta.solana.com",
          reconnect_interval: 5000
        },
        # ... other options
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

  defp get_section(section) do
    :ex_solana
    |> Application.get_env(section, [])
    |> Map.new(fn {k, v} -> {k, v || default({section, k})} end)
  end

  @doc """
  Validates the current configuration.

  This function checks if all required configuration options are set and valid.

  ## Returns

  `:ok` if the configuration is valid, otherwise `{:error, reason}`.

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
      validate_transaction_details()
    end
  end

  defp validate_url(key) do
    url = get(key)

    if is_binary(url) and String.starts_with?(url, ["http://", "https://", "ws://", "wss://"]) do
      :ok
    else
      {:error, "Invalid #{inspect(key)}: #{url}"}
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

  defp validate_transaction_details do
    details = get({:default, :transaction_details})

    if details in ["full", "signatures", "none"] do
      :ok
    else
      {:error, "Invalid transaction_details: #{details}"}
    end
  end
end
