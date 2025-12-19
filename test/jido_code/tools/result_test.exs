defmodule JidoCode.Tools.ResultTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Result

  describe "ok/4" do
    test "creates successful result with string content" do
      result = Result.ok("call_123", "read_file", "file contents", 45)

      assert result.tool_call_id == "call_123"
      assert result.tool_name == "read_file"
      assert result.status == :ok
      assert result.content == "file contents"
      assert result.duration_ms == 45
    end

    test "creates successful result with default duration" do
      result = Result.ok("call_123", "read_file", "contents")

      assert result.duration_ms == 0
    end

    test "formats map content as JSON" do
      result = Result.ok("call_123", "get_info", %{name: "test", value: 42})

      assert result.content == ~s({"name":"test","value":42})
    end

    test "formats list content as JSON" do
      result = Result.ok("call_123", "list_files", ["a.txt", "b.txt"])

      assert result.content == ~s(["a.txt","b.txt"])
    end

    test "formats other content via inspect" do
      result = Result.ok("call_123", "get_pid", self())

      assert result.content =~ "#PID<"
    end
  end

  describe "error/4" do
    test "creates error result with string reason" do
      result = Result.error("call_123", "read_file", "File not found", 12)

      assert result.tool_call_id == "call_123"
      assert result.tool_name == "read_file"
      assert result.status == :error
      assert result.content == "File not found"
      assert result.duration_ms == 12
    end

    test "creates error result with atom reason" do
      result = Result.error("call_123", "read_file", :enoent)

      assert result.content == "enoent"
    end

    test "creates error result with default duration" do
      result = Result.error("call_123", "read_file", "error")

      assert result.duration_ms == 0
    end

    test "unwraps {:error, reason} tuple" do
      result = Result.error("call_123", "read_file", {:error, "wrapped error"})

      assert result.content == "wrapped error"
    end

    test "extracts message from map with :message key" do
      result = Result.error("call_123", "api_call", %{message: "API error"})

      assert result.content == "API error"
    end

    test "inspects complex error reasons" do
      result = Result.error("call_123", "complex", {:complex, :error, 123})

      assert result.content == "{:complex, :error, 123}"
    end
  end

  describe "timeout/3" do
    test "creates timeout result" do
      result = Result.timeout("call_123", "slow_tool", 30_000)

      assert result.tool_call_id == "call_123"
      assert result.tool_name == "slow_tool"
      assert result.status == :timeout
      assert result.content == "Tool execution timed out after 30000ms"
      assert result.duration_ms == 30_000
    end
  end

  describe "ok?/1" do
    test "returns true for ok status" do
      result = Result.ok("id", "tool", "content")
      assert Result.ok?(result) == true
    end

    test "returns false for error status" do
      result = Result.error("id", "tool", "error")
      assert Result.ok?(result) == false
    end

    test "returns false for timeout status" do
      result = Result.timeout("id", "tool", 1000)
      assert Result.ok?(result) == false
    end
  end

  describe "error?/1" do
    test "returns false for ok status" do
      result = Result.ok("id", "tool", "content")
      assert Result.error?(result) == false
    end

    test "returns true for error status" do
      result = Result.error("id", "tool", "error")
      assert Result.error?(result) == true
    end

    test "returns true for timeout status" do
      result = Result.timeout("id", "tool", 1000)
      assert Result.error?(result) == true
    end
  end

  describe "to_llm_message/1" do
    test "formats ok result" do
      result = Result.ok("call_123", "read_file", "file contents")

      message = Result.to_llm_message(result)

      assert message == %{
               role: "tool",
               tool_call_id: "call_123",
               content: "file contents"
             }
    end

    test "formats error result with prefix" do
      result = Result.error("call_123", "read_file", "File not found")

      message = Result.to_llm_message(result)

      assert message == %{
               role: "tool",
               tool_call_id: "call_123",
               content: "Error: File not found"
             }
    end

    test "formats timeout result with prefix" do
      result = Result.timeout("call_123", "slow_tool", 30_000)

      message = Result.to_llm_message(result)

      assert message.role == "tool"
      assert message.tool_call_id == "call_123"
      assert message.content =~ "Error: Tool execution timed out"
    end
  end

  describe "to_llm_messages/1" do
    test "converts list of results" do
      results = [
        Result.ok("call_1", "tool_a", "result 1"),
        Result.error("call_2", "tool_b", "error 2"),
        Result.ok("call_3", "tool_c", "result 3")
      ]

      messages = Result.to_llm_messages(results)

      assert length(messages) == 3
      assert Enum.all?(messages, fn m -> m.role == "tool" end)
      assert Enum.at(messages, 0).tool_call_id == "call_1"
      assert Enum.at(messages, 1).content =~ "Error:"
      assert Enum.at(messages, 2).tool_call_id == "call_3"
    end

    test "returns empty list for empty input" do
      assert Result.to_llm_messages([]) == []
    end
  end
end
