defmodule JidoCode.Settings.CacheTest do
  use ExUnit.Case, async: false

  alias JidoCode.Settings.Cache

  setup do
    # Clear cache before each test
    Cache.clear()
    :ok
  end

  describe "start_link/1" do
    test "starts the cache process" do
      # Cache is already started by the application
      assert Process.whereis(Cache) != nil
    end

    test "creates ETS table" do
      table = Cache.table_name()
      assert :ets.whereis(table) != :undefined
    end
  end

  describe "get/0" do
    test "returns :miss when cache is empty" do
      assert Cache.get() == :miss
    end

    test "returns {:ok, settings} when cache has data" do
      settings = %{"provider" => "anthropic"}
      Cache.put(settings)

      assert Cache.get() == {:ok, settings}
    end
  end

  describe "put/1" do
    test "stores settings in cache" do
      settings = %{"provider" => "openai", "model" => "gpt-4o"}

      assert Cache.put(settings) == :ok
      assert Cache.get() == {:ok, settings}
    end

    test "overwrites existing cache" do
      Cache.put(%{"provider" => "anthropic"})
      Cache.put(%{"provider" => "openai"})

      assert Cache.get() == {:ok, %{"provider" => "openai"}}
    end
  end

  describe "clear/0" do
    test "clears the cache" do
      Cache.put(%{"provider" => "anthropic"})
      assert Cache.get() == {:ok, %{"provider" => "anthropic"}}

      assert Cache.clear() == :ok
      assert Cache.get() == :miss
    end

    test "returns :ok when cache is already empty" do
      assert Cache.clear() == :ok
    end
  end

  describe "table_name/0" do
    test "returns the ETS table name" do
      assert Cache.table_name() == :jido_code_settings_cache
    end
  end
end
