defmodule Jido.Signal.Serialization.SchemaTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Serialization.Schema

  describe "signal_schema/0" do
    test "returns Zoi schema" do
      schema = Schema.signal_schema()
      # Zoi schemas are complex structs, just verify it's not nil
      assert schema != nil
    end
  end

  describe "validate_signal/1" do
    test "accepts valid minimal Signal" do
      map = %{"type" => "test.event", "source" => "/test"}
      assert {:ok, validated} = Schema.validate_signal(map)
      assert validated["type"] == "test.event"
      assert validated["source"] == "/test"
    end

    test "accepts valid Signal with optional fields" do
      map = %{
        "type" => "test.event",
        "source" => "/test",
        "id" => "123",
        "specversion" => "1.0",
        "data" => %{"key" => "value"}
      }

      assert {:ok, validated} = Schema.validate_signal(map)
      assert validated["type"] == "test.event"
      assert validated["id"] == "123"
    end

    test "accepts Signal with version field" do
      map = %{
        "type" => "test.event",
        "source" => "/test",
        "jido_schema_version" => 1
      }

      assert {:ok, validated} = Schema.validate_signal(map)
      assert validated["jido_schema_version"] == 1
    end

    test "accepts Signal with extensions" do
      map = %{
        "type" => "test.event",
        "source" => "/test",
        "extensions" => %{"custom" => "data"}
      }

      assert {:ok, _} = Schema.validate_signal(map)
    end

    test "validates Signal with additional fields (CloudEvents extensions)" do
      map = %{
        "type" => "test.event",
        "source" => "/test",
        "custom_field" => "value",
        "another_ext" => 123
      }

      # Zoi validation passes, but unknown fields are stripped by default
      assert {:ok, validated} = Schema.validate_signal(map)
      assert validated["type"] == "test.event"
      assert validated["source"] == "/test"
    end

    test "rejects Signal with empty type" do
      map = %{"type" => "", "source" => "/test"}
      assert {:error, errors} = Schema.validate_signal(map)
      assert is_map(errors)
      assert Map.has_key?(errors, "type")
    end

    test "rejects Signal with empty source" do
      map = %{"type" => "test.event", "source" => ""}
      assert {:error, errors} = Schema.validate_signal(map)
      assert is_map(errors)
      assert Map.has_key?(errors, "source")
    end

    test "rejects Signal missing type" do
      map = %{"source" => "/test"}
      assert {:error, errors} = Schema.validate_signal(map)
      assert is_map(errors)
    end

    test "rejects Signal missing source" do
      map = %{"type" => "test.event"}
      assert {:error, errors} = Schema.validate_signal(map)
      assert is_map(errors)
    end

    test "returns structured errors for multiple failures" do
      map = %{"type" => "", "source" => ""}
      assert {:error, errors} = Schema.validate_signal(map)

      assert is_map(errors)
      # Should have errors for both fields
      assert map_size(errors) > 0
    end
  end

  describe "to_json_schema/0" do
    test "generates valid JSON Schema" do
      json_schema = Schema.to_json_schema()

      assert is_map(json_schema)
      assert json_schema.type == :object
      assert Map.has_key?(json_schema, :properties)
    end

    test "includes required CloudEvents fields in schema" do
      json_schema = Schema.to_json_schema()

      properties = json_schema.properties
      assert Map.has_key?(properties, "type")
      assert Map.has_key?(properties, "source")
    end
  end
end
