defmodule Jido.Signal.DispatchIntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Signal

  # Manually register the dispatch extension for testing
  setup_all do
    # Ensure the extension is registered since it might not be during testing
    Jido.Signal.Ext.Registry.register(Jido.Signal.Ext.Dispatch)
    :ok
  end

  test "dispatch extension works" do
    # Test 1: Create signal
    {:ok, signal1} =
      Signal.new("test.event", %{message: "hello"}, source: "/test")

    assert Signal.list_extensions(signal1) == []

    # Test 2: Add dispatch extension to signal
    {:ok, signal2} = Signal.put_extension(signal1, "dispatch", {:console, []})

    assert Signal.get_extension(signal2, "dispatch") == {:console, []}
    assert "dispatch" in Signal.list_extensions(signal2)

    # Test 3: Test extension serialization
    {:ok, ext_only_signal} = Signal.new("test.event", %{message: "hello"}, source: "/test")
    {:ok, ext_only_signal} = Signal.put_extension(ext_only_signal, "dispatch", {:console, []})

    {:ok, json} = Signal.serialize(ext_only_signal)
    assert is_binary(json)
    assert String.length(json) > 0

    # Check if extension is preserved
    {:ok, deserialized} = Signal.deserialize(json)
    assert Signal.get_extension(deserialized, "dispatch") == {:console, []}

    # Test 4: Validate invalid extension config
    {:ok, signal3} = Signal.new("test.event", %{}, source: "/test")
    {:error, error} = Signal.put_extension(signal3, "dispatch", {"invalid", []})
    assert error =~ "Invalid dispatch configuration"

    # Test 5: Complex dispatch configuration
    complex_dispatch = [
      {:logger, [level: :warning]},
      {:http, [url: "https://api.example.com", method: :post]}
    ]

    {:ok, signal4} = Signal.put_extension(signal1, "dispatch", complex_dispatch)
    retrieved = Signal.get_extension(signal4, "dispatch")

    # Compare the configs (accounting for possible reordering and defaults)
    assert length(retrieved) == length(complex_dispatch)
    [logger_config, http_config] = retrieved

    {:logger, logger_opts} = logger_config
    assert logger_opts[:level] == :warning

    {:http, http_opts} = http_config
    assert http_opts[:url] == "https://api.example.com"
    assert http_opts[:method] == :post
  end

  test "dispatch extension provides dispatch configuration" do
    dispatch_config = {:logger, [level: :debug]}

    # Using dispatch extension
    {:ok, signal} = Signal.new("test.event", %{}, source: "/test")
    {:ok, signal} = Signal.put_extension(signal, "dispatch", dispatch_config)

    assert Signal.get_extension(signal, "dispatch") == dispatch_config

    # Test extension serialization
    {:ok, json} = Signal.serialize(signal)
    {:ok, deserialized} = Signal.deserialize(json)

    # Extension should roundtrip correctly
    assert Signal.get_extension(deserialized, "dispatch") == dispatch_config
  end

  test "dispatch extension serializes to CloudEvents compliant format" do
    config = {:webhook, [url: "https://example.com", secret: "secret123"]}

    {:ok, signal} = Signal.new("test.event", %{}, source: "/test")
    {:ok, signal} = Signal.put_extension(signal, "dispatch", config)

    # Get the flattened attributes (like CloudEvents serialization would)
    attrs = Signal.flatten_extensions(signal)

    # Should have the dispatch attribute
    assert Map.has_key?(attrs, "dispatch")

    # Should be in proper CloudEvents format
    dispatch_data = attrs["dispatch"]
    assert is_map(dispatch_data)
    assert dispatch_data["adapter"] == "webhook"
    assert is_map(dispatch_data["opts"])

    # Round-trip through CloudEvents format
    {extensions, _remaining} = Signal.inflate_extensions(attrs)
    assert Map.has_key?(extensions, "dispatch")

    inflated_config = extensions["dispatch"]
    {:webhook, inflated_opts} = inflated_config
    assert inflated_opts[:url] == "https://example.com"
    assert inflated_opts[:secret] == "secret123"
  end
end
