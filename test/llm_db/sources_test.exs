defmodule LLMDB.SourcesTest do
  use ExUnit.Case, async: true

  alias LLMDB.Sources.{Config, Local}

  describe "Local source" do
    test "loads providers and models from TOML directory structure" do
      result = Local.load(%{dir: "priv/llm_db/local"})
      assert {:ok, data} = result
      assert is_map(data)
      assert map_size(data) > 0
    end

    test "returns error when directory not found" do
      result = Local.load(%{dir: "/nonexistent"})
      assert {:error, :directory_not_found} = result
    end

    test "requires dir parameter" do
      result = Local.load(%{})
      assert {:error, :dir_required} = result
    end
  end

  describe "Config source" do
    test "loads provider-keyed overrides (new format)" do
      overrides = %{
        openai: %{
          base_url: "https://staging-api.openai.com",
          models: [
            %{id: "gpt-4o", cost: %{input: 0.0, output: 0.0}},
            %{id: "gpt-4o-mini", limits: %{context: 200_000}}
          ]
        },
        anthropic: %{
          base_url: "https://proxy.example.com/anthropic",
          models: [
            %{id: "claude-3-5-sonnet", cost: %{input: 0.0, output: 0.0}}
          ]
        }
      }

      {:ok, data} = Config.load(%{overrides: overrides})

      assert map_size(data) == 2

      openai_provider = data["openai"]
      assert openai_provider.id == :openai
      assert openai_provider.base_url == "https://staging-api.openai.com"
      assert length(openai_provider.models) == 2

      gpt4o = Enum.find(openai_provider.models, fn m -> m.id == "gpt-4o" end)
      assert gpt4o.cost.input == 0.0
    end

    test "loads legacy format with providers/models keys" do
      overrides = %{
        providers: [%{id: :test_provider, name: "Test"}],
        models: [%{id: "test-model", provider: :test_provider}]
      }

      {:ok, data} = Config.load(%{overrides: overrides})

      assert map_size(data) == 1
      provider = data["test_provider"]
      assert provider.id == :test_provider
      assert provider.name == "Test"
      assert length(provider.models) == 1
      assert hd(provider.models).id == "test-model"
    end

    test "handles nil overrides" do
      {:ok, data} = Config.load(%{overrides: nil})

      assert data == %{}
    end

    test "handles empty overrides map" do
      {:ok, data} = Config.load(%{overrides: %{}})

      assert data == %{}
    end

    test "handles missing overrides parameter" do
      {:ok, data} = Config.load(%{})

      assert data == %{}
    end

    test "skips legacy keys in provider-keyed format" do
      overrides = %{
        openai: %{base_url: "https://api.openai.com"},
        providers: [%{id: :test}],
        models: [%{id: "test"}],
        exclude: %{openai: ["*"]}
      }

      {:ok, data} = Config.load(%{overrides: overrides})

      # Should only process openai, skip legacy keys
      assert map_size(data) == 1
      assert Map.has_key?(data, "openai")
      assert data["openai"].id == :openai
    end

    test "injects provider into models" do
      overrides = %{
        openai: %{
          models: [
            %{id: "gpt-4o"},
            %{id: "gpt-4o-mini"}
          ]
        }
      }

      {:ok, data} = Config.load(%{overrides: overrides})

      assert map_size(data) == 1
      provider = data["openai"]
      assert length(provider.models) == 2
    end
  end

  describe "Source behavior contract" do
    test "all sources return {:ok, data} format with nested structure" do
      # Config
      assert {:ok, data} = Config.load(%{overrides: %{}})
      assert is_map(data)
    end

    test "all sources handle error cases appropriately" do
      # Local returns error when dir not found
      assert {:error, :directory_not_found} = Local.load(%{dir: "/nonexistent"})

      # Local returns error when dir not provided
      assert {:error, :dir_required} = Local.load(%{})
    end
  end
end
