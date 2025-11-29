defmodule LLMDB.Sources.Config do
  @moduledoc """
  TEST-ONLY: Helper for injecting test data in tests.

  This module is NOT included in production builds. It exists solely to support
  tests that need to inject provider/model data without creating TOML files.

  Production users should use `LLMDB.Sources.Local` with TOML files for custom
  model definitions.

  ## Test Usage

      # In tests
      test_data = %{
        openai: %{
          id: :openai,
          models: [%{id: "gpt-4o", provider: :openai}]
        }
      }

      sources = [{LLMDB.Sources.Config, %{overrides: test_data}}]
      {:ok, snapshot} = Engine.run(sources: sources)

  ## Supported Formats

  ### Provider-keyed format (preferred)

      %{
        openai: %{
          base_url: "https://api.openai.com",
          models: [%{id: "gpt-4o", ...}]
        }
      }

  ### Legacy format (providers/models keys)

      %{
        providers: [%{id: :openai, ...}],
        models: [%{id: "gpt-4o", provider: :openai, ...}]
      }
  """

  @behaviour LLMDB.Source

  @impl true
  def load(%{overrides: overrides}) when is_map(overrides) do
    cond do
      # New format: provider-keyed map
      has_provider_keys?(overrides) ->
        transform_provider_keyed(overrides)

      # Legacy format: providers/models keys
      Map.has_key?(overrides, :providers) or Map.has_key?(overrides, :models) ->
        providers = Map.get(overrides, :providers, [])
        models = Map.get(overrides, :models, [])
        {:ok, convert_to_nested_format(providers, models)}

      # Empty map
      true ->
        {:ok, %{}}
    end
  end

  def load(%{overrides: nil}), do: {:ok, %{}}
  def load(_opts), do: {:ok, %{}}

  # Private helpers

  defp has_provider_keys?(overrides) do
    overrides
    |> Map.keys()
    |> Enum.any?(fn key -> is_atom(key) and key not in [:providers, :models, :exclude] end)
  end

  defp transform_provider_keyed(overrides) do
    result =
      Enum.reduce(overrides, %{}, fn {provider_id, data}, acc ->
        # Skip legacy keys
        if provider_id in [:providers, :models, :exclude] do
          acc
        else
          # Extract models list (special key)
          provider_models = Map.get(data, :models, [])

          # Everything except :models is provider-level data
          provider_data =
            data
            |> Map.delete(:models)
            |> Map.put(:id, provider_id)
            |> Map.put(:models, provider_models)

          Map.put(acc, to_string(provider_id), provider_data)
        end
      end)

    {:ok, result}
  end

  defp convert_to_nested_format(providers, models) do
    provider_map = Map.new(providers, fn p -> {to_string(p[:id] || p["id"]), p} end)

    models_by_provider =
      Enum.group_by(models, fn m ->
        to_string(m[:provider] || m["provider"])
      end)

    # Start with existing providers
    base_map =
      Enum.reduce(provider_map, %{}, fn {provider_id, provider_data}, acc ->
        provider_models = Map.get(models_by_provider, provider_id, [])
        provider_with_models = Map.put(provider_data, :models, provider_models)
        Map.put(acc, provider_id, provider_with_models)
      end)

    # Add any providers that only have models (no provider entry)
    Enum.reduce(models_by_provider, base_map, fn {provider_id, provider_models}, acc ->
      if Map.has_key?(acc, provider_id) do
        acc
      else
        # Create minimal provider entry with id and models
        provider_atom = String.to_existing_atom(provider_id)
        Map.put(acc, provider_id, %{id: provider_atom, models: provider_models})
      end
    end)
  end
end
