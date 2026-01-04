defmodule Karo.ChatDomainTest do
  use Karo.DataCase, async: false

  alias Karo.ChatDomain

  describe "get_or_create_conversation/2" do
    test "creates new conversation when none exists" do
      key = {nil, "channel_1", nil}

      assert {:ok, conversation} = ChatDomain.get_or_create_conversation(key)
      assert conversation.discord_channel_id == "channel_1"
      assert conversation.discord_guild_id == nil
      assert conversation.discord_thread_id == nil
      assert conversation.status == :open
      assert conversation.last_activity_at != nil
    end

    test "returns existing conversation when one exists (idempotent)" do
      key = {"guild_idem", "channel_idem", "thread_idem"}

      {:ok, conversation1} = ChatDomain.get_or_create_conversation(key)
      {:ok, conversation2} = ChatDomain.get_or_create_conversation(key)

      assert conversation1.id == conversation2.id
    end

    test "correctly maps conversation_key tuple to discord fields" do
      key = {"guild_123", "channel_456", "thread_789"}

      {:ok, conversation} = ChatDomain.get_or_create_conversation(key)

      assert conversation.discord_guild_id == "guild_123"
      assert conversation.discord_channel_id == "channel_456"
      assert conversation.discord_thread_id == "thread_789"
    end

    test "creates separate conversations for different keys" do
      key1 = {nil, "channel_1", nil}
      key2 = {nil, "channel_2", nil}

      {:ok, conv1} = ChatDomain.get_or_create_conversation(key1)
      {:ok, conv2} = ChatDomain.get_or_create_conversation(key2)

      assert conv1.id != conv2.id
    end
  end

  describe "create_message/4" do
    setup do
      {:ok, conversation} = ChatDomain.get_or_create_conversation({nil, "channel_test", nil})
      %{conversation: conversation}
    end

    test "creates message with correct role, content, and conversation_id", %{
      conversation: conversation
    } do
      {:ok, message} = ChatDomain.create_message(conversation.id, :user, "Hello world")

      assert message.conversation_id == conversation.id
      assert message.role == :user
      assert message.content == "Hello world"
    end

    test "extracts discord_user_id from meta", %{conversation: conversation} do
      meta = %{discord_user_id: "user_123", extra_field: "value"}

      {:ok, message} = ChatDomain.create_message(conversation.id, :user, "Test", meta)

      assert message.discord_user_id == "user_123"
      assert message.metadata == %{"extra_field" => "value"}
    end

    test "creates assistant message", %{conversation: conversation} do
      {:ok, message} = ChatDomain.create_message(conversation.id, :assistant, "I can help!")

      assert message.role == :assistant
      assert message.content == "I can help!"
      assert message.discord_user_id == nil
    end
  end

  describe "list_recent_messages/2" do
    setup do
      {:ok, conversation} = ChatDomain.get_or_create_conversation({nil, "channel_list", nil})
      %{conversation: conversation}
    end

    test "returns messages in inserted_at order (ascending)", %{conversation: conversation} do
      {:ok, _msg1} = ChatDomain.create_message(conversation.id, :user, "First")
      {:ok, _msg2} = ChatDomain.create_message(conversation.id, :assistant, "Second")
      {:ok, _msg3} = ChatDomain.create_message(conversation.id, :user, "Third")

      {:ok, messages} = ChatDomain.list_recent_messages(conversation.id)

      assert length(messages) == 3
      assert Enum.at(messages, 0).content == "First"
      assert Enum.at(messages, 1).content == "Second"
      assert Enum.at(messages, 2).content == "Third"
    end

    test "respects limit option", %{conversation: conversation} do
      for i <- 1..10 do
        ChatDomain.create_message(conversation.id, :user, "Message #{i}")
      end

      {:ok, messages} = ChatDomain.list_recent_messages(conversation.id, limit: 3)

      assert length(messages) == 3
    end

    test "returns empty list for conversation with no messages", %{conversation: conversation} do
      {:ok, messages} = ChatDomain.list_recent_messages(conversation.id)

      assert messages == []
    end
  end

  describe "close_conversation/1" do
    test "updates status to :closed" do
      {:ok, conversation} = ChatDomain.get_or_create_conversation({nil, "channel_close", nil})
      assert conversation.status == :open

      {:ok, closed} = ChatDomain.close_conversation(conversation.id)

      assert closed.status == :closed
    end

    test "updates last_activity_at" do
      {:ok, conversation} = ChatDomain.get_or_create_conversation({nil, "channel_close2", nil})
      original_time = conversation.last_activity_at

      Process.sleep(10)
      {:ok, closed} = ChatDomain.close_conversation(conversation.id)

      assert DateTime.compare(closed.last_activity_at, original_time) in [:gt, :eq]
    end
  end

  describe "touch_conversation/1" do
    test "updates only last_activity_at" do
      {:ok, conversation} = ChatDomain.get_or_create_conversation({nil, "channel_touch", nil})
      original_time = conversation.last_activity_at

      Process.sleep(10)
      {:ok, touched} = ChatDomain.touch_conversation(conversation.id)

      assert touched.status == :open
      assert DateTime.compare(touched.last_activity_at, original_time) in [:gt, :eq]
    end
  end
end
