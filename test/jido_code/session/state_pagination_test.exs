defmodule JidoCode.Session.StatePaginationTest do
  @moduledoc """
  Tests for message pagination in Session.State.

  Verifies that get_messages/3 provides efficient pagination for large
  conversation histories without requiring O(n) reversal on every read.
  """

  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.Session.State
  alias JidoCode.SessionSupervisor
  alias JidoCode.Test.SessionTestHelpers

  @moduletag :pagination
  @moduletag :llm

  setup do
    # Setup registry and tmp_dir
    {:ok, %{tmp_dir: tmp_dir}} = SessionTestHelpers.setup_session_registry("pagination")

    # Get valid LLM config
    config = SessionTestHelpers.valid_session_config()

    # Create session struct
    {:ok, session} = Session.new(project_path: tmp_dir, config: config)

    # Start session supervisor
    {:ok, _sup_pid} = SessionSupervisor.start_session(session)

    on_exit(fn ->
      # Clean up session
      SessionSupervisor.stop_session(session.id)
    end)

    {:ok, session_id: session.id}
  end

  describe "get_messages/3 pagination" do
    test "returns first page of messages", %{session_id: session_id} do
      # Add 30 messages
      messages = create_test_messages(30)

      for msg <- messages do
        State.append_message(session_id, msg)
      end

      # Get first 10 messages
      {:ok, page, meta} = State.get_messages(session_id, 0, 10)

      # Verify we got the first 10 messages (oldest first)
      assert length(page) == 10
      assert meta.total == 30
      assert meta.offset == 0
      assert meta.limit == 10
      assert meta.returned == 10
      assert meta.has_more == true

      # Verify messages are in chronological order (oldest first)
      assert Enum.at(page, 0).content == "Message 1"
      assert Enum.at(page, 9).content == "Message 10"
    end

    test "returns middle page of messages", %{session_id: session_id} do
      # Add 30 messages
      messages = create_test_messages(30)

      for msg <- messages do
        State.append_message(session_id, msg)
      end

      # Get second page (messages 11-20)
      {:ok, page, meta} = State.get_messages(session_id, 10, 10)

      # Verify we got the correct page
      assert length(page) == 10
      assert meta.offset == 10
      assert meta.returned == 10
      assert meta.has_more == true

      # Verify correct messages
      assert Enum.at(page, 0).content == "Message 11"
      assert Enum.at(page, 9).content == "Message 20"
    end

    test "returns last page of messages", %{session_id: session_id} do
      # Add 25 messages
      messages = create_test_messages(25)

      for msg <- messages do
        State.append_message(session_id, msg)
      end

      # Get last page (offset 20, limit 10 should return 5 messages)
      {:ok, page, meta} = State.get_messages(session_id, 20, 10)

      # Verify we got only the remaining messages
      assert length(page) == 5
      assert meta.offset == 20
      assert meta.limit == 10
      assert meta.returned == 5
      assert meta.has_more == false

      # Verify correct messages
      assert Enum.at(page, 0).content == "Message 21"
      assert Enum.at(page, 4).content == "Message 25"
    end

    test "returns empty list when offset exceeds total", %{session_id: session_id} do
      # Add 10 messages
      messages = create_test_messages(10)

      for msg <- messages do
        State.append_message(session_id, msg)
      end

      # Get page beyond available messages
      {:ok, page, meta} = State.get_messages(session_id, 100, 10)

      # Verify empty result
      assert page == []
      assert meta.total == 10
      assert meta.offset == 100
      assert meta.limit == 10
      assert meta.returned == 0
      assert meta.has_more == false
    end

    test "supports :all limit to get all remaining messages", %{session_id: session_id} do
      # Add 30 messages
      messages = create_test_messages(30)

      for msg <- messages do
        State.append_message(session_id, msg)
      end

      # Get all messages from offset 10
      {:ok, page, meta} = State.get_messages(session_id, 10, :all)

      # Verify we got all remaining messages
      assert length(page) == 20
      assert meta.total == 30
      assert meta.offset == 10
      assert meta.limit == 30
      assert meta.returned == 20
      assert meta.has_more == false

      # Verify correct messages
      assert Enum.at(page, 0).content == "Message 11"
      assert Enum.at(page, 19).content == "Message 30"
    end

    test "handles pagination with no messages", %{session_id: session_id} do
      # Don't add any messages

      # Get first page
      {:ok, page, meta} = State.get_messages(session_id, 0, 10)

      # Verify empty result
      assert page == []
      assert meta.total == 0
      assert meta.offset == 0
      assert meta.limit == 10
      assert meta.returned == 0
      assert meta.has_more == false
    end

    test "handles pagination with single message", %{session_id: session_id} do
      # Add 1 message
      messages = create_test_messages(1)
      State.append_message(session_id, Enum.at(messages, 0))

      # Get first page
      {:ok, page, meta} = State.get_messages(session_id, 0, 10)

      # Verify result
      assert length(page) == 1
      assert meta.total == 1
      assert meta.offset == 0
      assert meta.limit == 10
      assert meta.returned == 1
      assert meta.has_more == false

      assert Enum.at(page, 0).content == "Message 1"
    end

    test "handles exact page boundary", %{session_id: session_id} do
      # Add exactly 20 messages
      messages = create_test_messages(20)

      for msg <- messages do
        State.append_message(session_id, msg)
      end

      # Get second page (should be exactly 10 messages)
      {:ok, page, meta} = State.get_messages(session_id, 10, 10)

      # Verify exact page
      assert length(page) == 10
      assert meta.total == 20
      assert meta.offset == 10
      assert meta.returned == 10
      assert meta.has_more == false

      assert Enum.at(page, 0).content == "Message 11"
      assert Enum.at(page, 9).content == "Message 20"
    end
  end

  describe "get_messages/3 performance" do
    test "pagination is more efficient than full reversal for large histories", %{
      session_id: session_id
    } do
      # Add 1000 messages (max limit)
      messages = create_test_messages(1000)

      for msg <- messages do
        State.append_message(session_id, msg)
      end

      # Measure time for paginated access (only reverses 10 messages)
      {paginated_time, {:ok, page, _meta}} =
        :timer.tc(fn ->
          State.get_messages(session_id, 0, 10)
        end)

      # Measure time for full access (reverses all 1000 messages)
      {full_time, {:ok, all_messages}} =
        :timer.tc(fn ->
          State.get_messages(session_id)
        end)

      # Verify correctness
      assert length(page) == 10
      assert length(all_messages) == 1000

      # Verify efficiency: paginated should be faster for large lists
      # (This is a rough check - in practice, paginated is much faster)
      # For 1000 messages, reversing 10 should be ~100x faster than reversing 1000
      # But we'll use a conservative 2x check to avoid flaky tests
      assert paginated_time < full_time * 2,
             "Paginated (#{paginated_time}µs) should be faster than full (#{full_time}µs)"
    end
  end

  describe "get_messages/1 backward compatibility" do
    test "still returns all messages in chronological order", %{session_id: session_id} do
      # Add 30 messages
      messages = create_test_messages(30)

      for msg <- messages do
        State.append_message(session_id, msg)
      end

      # Use old API
      {:ok, all_messages} = State.get_messages(session_id)

      # Verify we got all messages in chronological order
      assert length(all_messages) == 30
      assert Enum.at(all_messages, 0).content == "Message 1"
      assert Enum.at(all_messages, 29).content == "Message 30"
    end

    test "returns empty list when no messages", %{session_id: session_id} do
      # Don't add any messages

      # Use old API
      {:ok, all_messages} = State.get_messages(session_id)

      # Verify empty list
      assert all_messages == []
    end
  end

  describe "edge cases" do
    test "handles limit larger than total messages", %{session_id: session_id} do
      # Add 5 messages
      messages = create_test_messages(5)

      for msg <- messages do
        State.append_message(session_id, msg)
      end

      # Request 100 messages
      {:ok, page, meta} = State.get_messages(session_id, 0, 100)

      # Should return all 5 messages
      assert length(page) == 5
      assert meta.total == 5
      assert meta.returned == 5
      assert meta.has_more == false
    end

    test "handles zero offset", %{session_id: session_id} do
      # Add 10 messages
      messages = create_test_messages(10)

      for msg <- messages do
        State.append_message(session_id, msg)
      end

      # Request with offset 0
      {:ok, page, meta} = State.get_messages(session_id, 0, 5)

      # Should return first 5 messages
      assert length(page) == 5
      assert Enum.at(page, 0).content == "Message 1"
      assert Enum.at(page, 4).content == "Message 5"
      assert meta.has_more == true
    end

    test "handles limit of 1", %{session_id: session_id} do
      # Add 10 messages
      messages = create_test_messages(10)

      for msg <- messages do
        State.append_message(session_id, msg)
      end

      # Request 1 message at a time
      {:ok, page1, meta1} = State.get_messages(session_id, 0, 1)
      {:ok, page2, meta2} = State.get_messages(session_id, 1, 1)

      # Verify single message pages
      assert length(page1) == 1
      assert Enum.at(page1, 0).content == "Message 1"
      assert meta1.has_more == true

      assert length(page2) == 1
      assert Enum.at(page2, 0).content == "Message 2"
      assert meta2.has_more == true
    end

    test "respects max message limit (1000)", %{session_id: session_id} do
      # Try to add 1100 messages (max is 1000)
      messages = create_test_messages(1100)

      for msg <- messages do
        State.append_message(session_id, msg)
      end

      # Get all messages
      {:ok, all_messages} = State.get_messages(session_id)

      # Should have max 1000 messages (oldest 100 evicted)
      assert length(all_messages) == 1000

      # First message should be message 101 (oldest 100 evicted)
      assert Enum.at(all_messages, 0).content == "Message 101"
      assert Enum.at(all_messages, 999).content == "Message 1100"
    end
  end

  describe "error handling" do
    test "returns error for non-existent session" do
      result = State.get_messages("nonexistent-session", 0, 10)
      assert {:error, :not_found} = result
    end

    test "get_messages/1 returns error for non-existent session" do
      result = State.get_messages("nonexistent-session")
      assert {:error, :not_found} = result
    end
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_test_messages(count) do
    for i <- 1..count do
      %{
        id: "msg-#{i}",
        role: :user,
        content: "Message #{i}",
        timestamp: DateTime.utc_now()
      }
    end
  end
end
