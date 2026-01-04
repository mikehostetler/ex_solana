defmodule Karo.ChatSessionTest do
  use Karo.DataCase, async: false
  use Mimic

  alias Karo.ChatSession
  alias Karo.ChatDomain
  alias Karo.LLM

  setup :set_mimic_global

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Karo.Repo, {:shared, self()})
    :ok
  end

  describe "session lifecycle" do
    test "starts and registers in ChatRegistry" do
      conversation_key = {"guild_lc1", "channel_lifecycle_1", "thread_lc1"}

      {:ok, pid} = ChatSession.start_link(conversation_key: conversation_key)

      assert is_pid(pid)
      assert Process.alive?(pid)

      lookup = Registry.lookup(Karo.ChatRegistry, conversation_key)
      assert [{^pid, _}] = lookup
    end

    test "creates conversation on init" do
      conversation_key = {"guild_lc2", "channel_lifecycle_2", "thread_lc2"}

      {:ok, _pid} = ChatSession.start_link(conversation_key: conversation_key)

      {:ok, conversation} = ChatDomain.get_or_create_conversation(conversation_key)
      assert conversation.discord_channel_id == "channel_lifecycle_2"
    end

    test "loads existing messages on init" do
      conversation_key = {"guild_lc3", "channel_lifecycle_3", "thread_lc3"}

      {:ok, conversation} = ChatDomain.get_or_create_conversation(conversation_key)
      {:ok, _} = ChatDomain.create_message(conversation.id, :user, "Old message")
      {:ok, _} = ChatDomain.create_message(conversation.id, :assistant, "Old response")

      stub(LLM, :chat, fn _messages ->
        {:ok, "New response"}
      end)

      {:ok, pid} = ChatSession.start_link(conversation_key: conversation_key)

      {:ok, _response} = ChatSession.send_message(pid, "user_1", "New message")

      {:ok, messages} = ChatDomain.list_recent_messages(conversation.id)
      assert length(messages) == 4
    end
  end

  describe "message handling" do
    test "persists user and assistant messages" do
      conversation_key = {"guild_msg1", "channel_msg_1", "thread_msg1"}

      stub(LLM, :chat, fn _messages ->
        {:ok, "Hello from Karo!"}
      end)

      {:ok, pid} = ChatSession.start_link(conversation_key: conversation_key)
      {:ok, response} = ChatSession.send_message(pid, "user_123", "Hello!")

      assert response == "Hello from Karo!"

      {:ok, conversation} = ChatDomain.get_or_create_conversation(conversation_key)
      {:ok, messages} = ChatDomain.list_recent_messages(conversation.id)

      assert length(messages) == 2

      [user_msg, assistant_msg] = messages
      assert user_msg.role == :user
      assert user_msg.content == "Hello!"
      assert user_msg.discord_user_id == "user_123"

      assert assistant_msg.role == :assistant
      assert assistant_msg.content == "Hello from Karo!"
    end

    test "returns response from LLM" do
      conversation_key = {"guild_msg2", "channel_msg_2", "thread_msg2"}

      stub(LLM, :chat, fn messages ->
        last_user_msg = Enum.find(messages, &(&1.role == :user))
        {:ok, "Echo: #{last_user_msg.content}"}
      end)

      {:ok, pid} = ChatSession.start_link(conversation_key: conversation_key)
      {:ok, response} = ChatSession.send_message(pid, "user_1", "Test message")

      assert response == "Echo: Test message"
    end

    test "truncates messages to max_context_messages" do
      Application.put_env(:karo, :chat_session, max_context_messages: 4)

      on_exit(fn ->
        Application.delete_env(:karo, :chat_session)
      end)

      conversation_key = {"guild_msg4", "channel_msg_4", "thread_msg4"}

      stub(LLM, :chat, fn _messages ->
        {:ok, "Response"}
      end)

      {:ok, pid} = ChatSession.start_link(conversation_key: conversation_key)

      for i <- 1..5 do
        ChatSession.send_message(pid, "user_1", "Message #{i}")
      end

      {:ok, conversation} = ChatDomain.get_or_create_conversation(conversation_key)
      {:ok, all_messages} = ChatDomain.list_recent_messages(conversation.id, limit: 100)

      assert length(all_messages) == 10
    end

    test "LLM receives messages with system prompt" do
      conversation_key = {"guild_msg5", "channel_msg_5", "thread_msg5"}

      stub(LLM, :chat, fn messages ->
        system_msg = Enum.find(messages, &(&1.role == :system))
        assert system_msg != nil
        assert system_msg.content =~ "Karo"
        {:ok, "Got system prompt"}
      end)

      {:ok, pid} = ChatSession.start_link(conversation_key: conversation_key)
      {:ok, _} = ChatSession.send_message(pid, "user_1", "Hello")
    end
  end

  describe "send_message/3 via conversation_key" do
    test "can send message using conversation_key tuple" do
      conversation_key = {"guild_key1", "channel_key_1", "thread_key1"}

      stub(LLM, :chat, fn _messages ->
        {:ok, "Response via key"}
      end)

      {:ok, _pid} = ChatSession.start_link(conversation_key: conversation_key)
      {:ok, response} = ChatSession.send_message(conversation_key, "user_1", "Hello")

      assert response == "Response via key"
    end
  end
end
