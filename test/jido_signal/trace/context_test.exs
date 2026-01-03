defmodule Jido.Signal.Trace.ContextTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Trace.Context

  describe "new/0,1" do
    test "generates valid W3C trace_id (32 hex chars)" do
      {:ok, ctx} = Context.new()
      assert is_binary(ctx.trace_id)
      assert byte_size(ctx.trace_id) == 32
      assert String.match?(ctx.trace_id, ~r/^[0-9a-f]+$/)
    end

    test "generates valid W3C span_id (16 hex chars)" do
      {:ok, ctx} = Context.new()
      assert is_binary(ctx.span_id)
      assert byte_size(ctx.span_id) == 16
      assert String.match?(ctx.span_id, ~r/^[0-9a-f]+$/)
    end

    test "sets parent_span_id to nil for root" do
      {:ok, ctx} = Context.new()
      assert ctx.parent_span_id == nil
    end

    test "generates unique IDs on each call" do
      {:ok, ctx1} = Context.new()
      {:ok, ctx2} = Context.new()
      assert ctx1.trace_id != ctx2.trace_id
      assert ctx1.span_id != ctx2.span_id
    end

    test "accepts causation_id option" do
      {:ok, ctx} = Context.new(causation_id: "external-request-123")
      assert ctx.causation_id == "external-request-123"
    end

    test "accepts tracestate option" do
      {:ok, ctx} = Context.new(tracestate: "vendor1=value1,vendor2=value2")
      assert ctx.tracestate == "vendor1=value1,vendor2=value2"
    end
  end

  describe "new!/0,1" do
    test "returns context directly" do
      ctx = Context.new!()
      assert %Context{} = ctx
      assert is_binary(ctx.trace_id)
    end
  end

  describe "child_of/2" do
    test "shares parent trace_id" do
      parent = Context.new!()
      {:ok, child} = Context.child_of(parent, "signal-123")
      assert child.trace_id == parent.trace_id
    end

    test "generates new span_id for child" do
      parent = Context.new!()
      {:ok, child} = Context.child_of(parent, "signal-123")
      assert child.span_id != parent.span_id
      assert byte_size(child.span_id) == 16
    end

    test "sets parent_span_id to parent's span_id" do
      parent = Context.new!()
      {:ok, child} = Context.child_of(parent, "signal-123")
      assert child.parent_span_id == parent.span_id
    end

    test "sets causation_id to the given value" do
      parent = Context.new!()
      {:ok, child} = Context.child_of(parent, "signal-123")
      assert child.causation_id == "signal-123"
    end

    test "inherits tracestate from parent" do
      parent = Context.new!(tracestate: "vendor=value")
      {:ok, child} = Context.child_of(parent, "signal-123")
      assert child.tracestate == "vendor=value"
    end

    test "handles nil parent by creating root" do
      {:ok, child} = Context.child_of(nil, "signal-123")
      assert is_binary(child.trace_id)
      assert is_binary(child.span_id)
      assert child.parent_span_id == nil
      assert child.causation_id == "signal-123"
    end

    test "handles nil causation_id" do
      parent = Context.new!()
      {:ok, child} = Context.child_of(parent, nil)
      assert child.causation_id == nil
    end
  end

  describe "child_of!/2" do
    test "returns context directly" do
      parent = Context.new!()
      child = Context.child_of!(parent, "signal-123")
      assert %Context{} = child
      assert child.trace_id == parent.trace_id
    end
  end

  describe "to_traceparent/1" do
    test "formats as W3C traceparent" do
      ctx = %Context{
        trace_id: "4bf92f3577b34da6a3ce929d0e0e4736",
        span_id: "00f067aa0ba902b7"
      }

      traceparent = Context.to_traceparent(ctx)
      assert traceparent == "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    end

    test "uses version 00 and sampled flag 01" do
      ctx = Context.new!()
      traceparent = Context.to_traceparent(ctx)

      [version, _trace_id, _span_id, flags] = String.split(traceparent, "-")
      assert version == "00"
      assert flags == "01"
    end
  end

  describe "from_traceparent/1" do
    test "parses valid traceparent" do
      traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

      {:ok, ctx} = Context.from_traceparent(traceparent)

      assert ctx.trace_id == "4bf92f3577b34da6a3ce929d0e0e4736"
      assert ctx.span_id == "00f067aa0ba902b7"
      assert ctx.parent_span_id == nil
      assert ctx.causation_id == nil
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_traceparent} = Context.from_traceparent("invalid")
      assert {:error, :invalid_traceparent} = Context.from_traceparent("")
      assert {:error, :invalid_traceparent} = Context.from_traceparent(nil)
    end

    test "returns error for wrong trace_id length" do
      assert {:error, :invalid_traceparent} =
               Context.from_traceparent("00-short-00f067aa0ba902b7-01")
    end

    test "returns error for wrong span_id length" do
      assert {:error, :invalid_traceparent} =
               Context.from_traceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-short-01")
    end

    test "returns error for non-hex characters" do
      assert {:error, :invalid_traceparent} =
               Context.from_traceparent("00-GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG-00f067aa0ba902b7-01")
    end

    test "roundtrip with to_traceparent" do
      ctx = Context.new!()
      traceparent = Context.to_traceparent(ctx)
      {:ok, parsed} = Context.from_traceparent(traceparent)

      assert parsed.trace_id == ctx.trace_id
      assert parsed.span_id == ctx.span_id
    end
  end

  describe "child_from_traceparent/2" do
    test "creates child span from traceparent" do
      traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

      {:ok, child} = Context.child_from_traceparent(traceparent, causation_id: "req-123")

      assert child.trace_id == "4bf92f3577b34da6a3ce929d0e0e4736"
      assert child.parent_span_id == "00f067aa0ba902b7"
      assert child.span_id != "00f067aa0ba902b7"
      assert byte_size(child.span_id) == 16
      assert child.causation_id == "req-123"
    end

    test "returns error for invalid traceparent" do
      assert {:error, :invalid_traceparent} = Context.child_from_traceparent("invalid")
    end

    test "accepts tracestate option" do
      traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

      {:ok, child} = Context.child_from_traceparent(traceparent, tracestate: "vendor=value")

      assert child.tracestate == "vendor=value"
    end
  end

  describe "valid?/1" do
    test "returns true for valid context" do
      ctx = Context.new!()
      assert Context.valid?(ctx) == true
    end

    test "returns false for nil" do
      assert Context.valid?(nil) == false
    end

    test "returns false for invalid trace_id length" do
      ctx = %Context{trace_id: "short", span_id: "00f067aa0ba902b7"}
      assert Context.valid?(ctx) == false
    end

    test "returns false for invalid span_id length" do
      ctx = %Context{trace_id: "4bf92f3577b34da6a3ce929d0e0e4736", span_id: "short"}
      assert Context.valid?(ctx) == false
    end

    test "returns false for non-hex trace_id" do
      ctx = %Context{
        trace_id: "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
        span_id: "00f067aa0ba902b7"
      }

      assert Context.valid?(ctx) == false
    end
  end

  describe "to_map/1" do
    test "converts context to map without nil values" do
      ctx = Context.new!()
      map = Context.to_map(ctx)

      assert is_map(map)
      assert map.trace_id == ctx.trace_id
      assert map.span_id == ctx.span_id
      refute Map.has_key?(map, :parent_span_id)
      refute Map.has_key?(map, :causation_id)
    end

    test "includes non-nil optional fields" do
      ctx = Context.new!(causation_id: "signal-123", tracestate: "vendor=value")
      map = Context.to_map(ctx)

      assert map.causation_id == "signal-123"
      assert map.tracestate == "vendor=value"
    end
  end

  describe "from_map/1" do
    test "creates context from atom-keyed map" do
      map = %{trace_id: "4bf92f3577b34da6a3ce929d0e0e4736", span_id: "00f067aa0ba902b7"}
      {:ok, ctx} = Context.from_map(map)

      assert ctx.trace_id == "4bf92f3577b34da6a3ce929d0e0e4736"
      assert ctx.span_id == "00f067aa0ba902b7"
    end

    test "creates context from string-keyed map" do
      map = %{"trace_id" => "4bf92f3577b34da6a3ce929d0e0e4736", "span_id" => "00f067aa0ba902b7"}
      {:ok, ctx} = Context.from_map(map)

      assert ctx.trace_id == "4bf92f3577b34da6a3ce929d0e0e4736"
      assert ctx.span_id == "00f067aa0ba902b7"
    end

    test "includes optional fields" do
      map = %{
        trace_id: "4bf92f3577b34da6a3ce929d0e0e4736",
        span_id: "00f067aa0ba902b7",
        parent_span_id: "abcdef0123456789",
        causation_id: "signal-xyz"
      }

      {:ok, ctx} = Context.from_map(map)

      assert ctx.parent_span_id == "abcdef0123456789"
      assert ctx.causation_id == "signal-xyz"
    end

    test "returns error for invalid map" do
      assert {:error, :invalid_map} = Context.from_map(%{})
      assert {:error, :invalid_map} = Context.from_map(%{trace_id: "abc"})
    end
  end

  describe "from_map!/1" do
    test "returns context directly" do
      map = %{trace_id: "4bf92f3577b34da6a3ce929d0e0e4736", span_id: "00f067aa0ba902b7"}
      ctx = Context.from_map!(map)
      assert %Context{} = ctx
    end

    test "raises on invalid map" do
      assert_raise RuntimeError, fn ->
        Context.from_map!(%{})
      end
    end
  end

  describe "to_telemetry_metadata/1" do
    test "returns prefixed metadata" do
      ctx = %Context{
        trace_id: "abc123",
        span_id: "def456",
        parent_span_id: "parent789",
        causation_id: "signal-xyz"
      }

      meta = Context.to_telemetry_metadata(ctx)

      assert meta.jido_trace_id == "abc123"
      assert meta.jido_span_id == "def456"
      assert meta.jido_parent_span_id == "parent789"
      assert meta.jido_causation_id == "signal-xyz"
    end

    test "returns nil values for nil context" do
      meta = Context.to_telemetry_metadata(nil)

      assert meta.jido_trace_id == nil
      assert meta.jido_span_id == nil
      assert meta.jido_parent_span_id == nil
      assert meta.jido_causation_id == nil
    end

    test "handles context with nil optional fields" do
      ctx = Context.new!()
      meta = Context.to_telemetry_metadata(ctx)

      assert meta.jido_trace_id == ctx.trace_id
      assert meta.jido_span_id == ctx.span_id
      assert meta.jido_parent_span_id == nil
      assert meta.jido_causation_id == nil
    end
  end

  describe "roundtrip" do
    test "to_map and from_map preserve all fields" do
      original = Context.new!(causation_id: "signal-123", tracestate: "vendor=value")
      {:ok, parent} = Context.child_of(original, "parent-signal")

      map = Context.to_map(parent)
      {:ok, restored} = Context.from_map(map)

      assert restored.trace_id == parent.trace_id
      assert restored.span_id == parent.span_id
      assert restored.parent_span_id == parent.parent_span_id
      assert restored.causation_id == parent.causation_id
      assert restored.tracestate == parent.tracestate
    end
  end
end
