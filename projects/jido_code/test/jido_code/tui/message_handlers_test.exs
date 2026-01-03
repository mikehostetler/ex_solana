defmodule JidoCode.TUI.MessageHandlersTest do
  use ExUnit.Case, async: true

  alias JidoCode.TUI.MessageHandlers

  describe "extract_usage/1" do
    test "returns nil for nil metadata" do
      assert MessageHandlers.extract_usage(nil) == nil
    end

    test "returns nil for metadata without usage" do
      assert MessageHandlers.extract_usage(%{status: 200}) == nil
    end

    test "extracts usage with atom keys" do
      metadata = %{
        usage: %{
          input_tokens: 100,
          output_tokens: 200,
          total_cost: 0.0015
        }
      }

      assert %{input_tokens: 100, output_tokens: 200, total_cost: 0.0015} =
               MessageHandlers.extract_usage(metadata)
    end

    test "extracts usage with string keys" do
      metadata = %{
        "usage" => %{
          "input_tokens" => 150,
          "output_tokens" => 250,
          "total_cost" => 0.002
        }
      }

      assert %{input_tokens: 150, output_tokens: 250, total_cost: 0.002} =
               MessageHandlers.extract_usage(metadata)
    end

    test "extracts usage with alternate key names (input/output)" do
      metadata = %{
        usage: %{
          input: 50,
          output: 75,
          cost: 0.001
        }
      }

      result = MessageHandlers.extract_usage(metadata)
      assert result.input_tokens == 50
      assert result.output_tokens == 75
      assert result.total_cost == 0.001
    end

    test "defaults missing token values to 0" do
      metadata = %{usage: %{total_cost: 0.001}}

      result = MessageHandlers.extract_usage(metadata)
      assert result.input_tokens == 0
      assert result.output_tokens == 0
      assert result.total_cost == 0.001
    end

    test "defaults missing cost to 0.0" do
      metadata = %{usage: %{input_tokens: 100, output_tokens: 200}}

      result = MessageHandlers.extract_usage(metadata)
      assert result.total_cost == 0.0
    end

    test "returns nil for non-map usage value" do
      assert MessageHandlers.extract_usage(%{usage: "invalid"}) == nil
    end
  end

  describe "accumulate_usage/2" do
    test "returns current usage when new_usage is nil" do
      current = %{input_tokens: 100, output_tokens: 200, total_cost: 0.001}
      assert MessageHandlers.accumulate_usage(current, nil) == current
    end

    test "sums token counts and costs" do
      current = %{input_tokens: 100, output_tokens: 200, total_cost: 0.001}
      new_usage = %{input_tokens: 50, output_tokens: 100, total_cost: 0.0005}

      result = MessageHandlers.accumulate_usage(current, new_usage)

      assert result.input_tokens == 150
      assert result.output_tokens == 300
      assert result.total_cost == 0.0015
    end

    test "handles missing keys in current usage" do
      current = %{}
      new_usage = %{input_tokens: 50, output_tokens: 100, total_cost: 0.0005}

      result = MessageHandlers.accumulate_usage(current, new_usage)

      assert result.input_tokens == 50
      assert result.output_tokens == 100
      assert result.total_cost == 0.0005
    end

    test "handles missing keys in new usage" do
      current = %{input_tokens: 100, output_tokens: 200, total_cost: 0.001}
      new_usage = %{}

      result = MessageHandlers.accumulate_usage(current, new_usage)

      assert result.input_tokens == 100
      assert result.output_tokens == 200
      assert result.total_cost == 0.001
    end
  end

  describe "format_usage_compact/1" do
    test "returns default for nil usage" do
      assert MessageHandlers.format_usage_compact(nil) == "🎟️ 0 in / 0 out"
    end

    test "formats input/output tokens and cost with icon" do
      usage = %{input_tokens: 150, output_tokens: 350, total_cost: 0.0025}
      result = MessageHandlers.format_usage_compact(usage)

      assert result =~ "🎟️"
      assert result =~ "150 in"
      assert result =~ "350 out"
      assert result =~ "$0.0025"
    end

    test "formats zero cost" do
      usage = %{input_tokens: 100, output_tokens: 200, total_cost: 0.0}
      result = MessageHandlers.format_usage_compact(usage)

      assert result =~ "🎟️"
      assert result =~ "100 in"
      assert result =~ "200 out"
      assert result =~ "$0.0000"
    end
  end

  describe "format_usage_detailed/1" do
    test "returns empty string for nil usage" do
      assert MessageHandlers.format_usage_detailed(nil) == ""
    end

    test "formats input/output tokens and cost with icon" do
      usage = %{input_tokens: 150, output_tokens: 350, total_cost: 0.0025}
      result = MessageHandlers.format_usage_detailed(usage)

      assert result =~ "🎟️"
      assert result =~ "150 in"
      assert result =~ "350 out"
      assert result =~ "Cost:"
      assert result =~ "$0.0025"
    end

    test "includes token icon" do
      usage = %{input_tokens: 100, output_tokens: 200, total_cost: 0.001}
      result = MessageHandlers.format_usage_detailed(usage)

      assert result =~ "🎟️"
    end
  end

  describe "default_usage/0" do
    test "returns initial usage map with zeros" do
      default = MessageHandlers.default_usage()

      assert default.input_tokens == 0
      assert default.output_tokens == 0
      assert default.total_cost == 0.0
    end
  end
end
