defmodule JidoClaudeTest do
  use ExUnit.Case, async: true

  describe "JidoClaude" do
    test "returns version" do
      assert JidoClaude.version() == "0.1.0"
    end
  end
end
