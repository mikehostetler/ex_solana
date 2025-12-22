defmodule JidoCode.Config.ProviderKeys do
  @moduledoc """
  Shared provider to API key name mappings.

  This module centralizes the mapping between provider names and their
  corresponding API key names in the keyring. It also maintains a list
  of local providers that don't require API keys.

  ## Security

  The provider keys whitelist prevents atom exhaustion from arbitrary
  user input. Unknown providers return `:unknown_provider_api_key`.
  """

  # Local providers that don't require API keys
  @local_providers ["lmstudio", "llama", "ollama"]

  # Known provider to API key name mapping
  # This whitelist prevents atom exhaustion from arbitrary user input
  @provider_keys %{
    "openai" => :openai_api_key,
    "anthropic" => :anthropic_api_key,
    "openrouter" => :openrouter_api_key,
    "azure" => :azure_api_key,
    "google" => :google_api_key,
    "gemini" => :google_api_key,
    "cohere" => :cohere_api_key,
    "mistral" => :mistral_api_key,
    "groq" => :groq_api_key,
    "together" => :together_api_key,
    "fireworks" => :fireworks_api_key,
    "deepseek" => :deepseek_api_key,
    "perplexity" => :perplexity_api_key,
    "xai" => :xai_api_key,
    "ollama" => :ollama_api_key,
    "cerebras" => :cerebras_api_key,
    "sambanova" => :sambanova_api_key,
    # Local providers (no API key required)
    "lmstudio" => :lmstudio_api_key,
    "llama" => :llama_api_key
  }

  @doc """
  Returns the list of local providers that don't require API keys.
  """
  @spec local_providers() :: [String.t()]
  def local_providers, do: @local_providers

  @doc """
  Checks if a provider is a local provider (doesn't require API key).
  """
  @spec local_provider?(String.t()) :: boolean()
  def local_provider?(provider), do: provider in @local_providers

  @doc """
  Maps a provider name to its API key name in the keyring.

  Returns `:unknown_provider_api_key` for unknown providers to prevent
  atom exhaustion from arbitrary user input.

  ## Examples

      iex> JidoCode.Config.ProviderKeys.to_key_name("anthropic")
      :anthropic_api_key

      iex> JidoCode.Config.ProviderKeys.to_key_name("unknown")
      :unknown_provider_api_key
  """
  @spec to_key_name(String.t()) :: atom()
  def to_key_name(provider) do
    Map.get(@provider_keys, provider, :unknown_provider_api_key)
  end

  @doc """
  Returns all known provider names.
  """
  @spec known_providers() :: [String.t()]
  def known_providers, do: Map.keys(@provider_keys)
end
