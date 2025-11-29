# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.IexChatIntegrationTest do
  use ExUnit.Case, async: true

  defmodule FakeReqLLM do
    @moduledoc """
    A fake ReqLLM implementation for testing tool-call loops.
    """

    def stream_text(_model, messages, _opts) do
      # Check if this is the first call (no tool results) or follow-up
      has_tool_result = Enum.any?(messages, &match?(%{role: "tool"}, &1))

      if has_tool_result do
        # After tool execution, return final response
        stream = [
          %{type: :content, text: "I found "},
          %{type: :content, text: "the records you requested."}
        ]

        {:ok, %{stream: stream}}
      else
        # First call: simulate a tool call
        stream = [
          %{
            type: :tool_call,
            id: "call_123",
            name: "read_test_resource",
            arguments: %{}
          }
        ]

        {:ok, %{stream: stream}}
      end
    end
  end

  setup do
    # Capture IO to prevent output during tests
    ExUnit.CaptureIO.capture_io(fn ->
      :ok
    end)

    :ok
  end

  @tag :skip
  test "iex_chat can use injected req_llm module for testing" do
    # This test is skipped because iex_chat enters an interactive loop
    # that expects user input. This demonstrates the pattern for future
    # integration tests that can be run non-interactively.

    # Example usage (would need modification to iex_chat to support non-interactive mode):
    # AshAi.iex_chat(nil,
    #   req_llm: FakeReqLLM,
    #   otp_app: :ash_ai,
    #   actions: [{TestResource, [:read]}],
    #   model: "test:model"
    # )

    assert true
  end

  test "Options validates req_llm parameter" do
    opts =
      AshAi.Options.validate!(
        req_llm: FakeReqLLM,
        otp_app: :ash_ai
      )

    assert opts.req_llm == FakeReqLLM
  end

  test "Options defaults req_llm to ReqLLM" do
    opts = AshAi.Options.validate!(otp_app: :ash_ai)
    assert opts.req_llm == ReqLLM
  end
end
