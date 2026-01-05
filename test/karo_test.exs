defmodule KaroTest do
  use ExUnit.Case, async: false

  describe "send_message/4" do
    test "sends a message and receives a response" do
      {:ok, response} = Karo.send_message("channel_123", "user_456", "Hello!")
      assert is_binary(response)
      assert response =~ "Karo"
    end

    test "handles guild_id option" do
      {:ok, response} =
        Karo.send_message("channel_123", "user_456", "Hello!", guild_id: "guild_789")

      assert is_binary(response)
    end

    test "handles thread_id option" do
      {:ok, response} =
        Karo.send_message("channel_123", "user_456", "Hello!",
          guild_id: "guild_789",
          thread_id: "thread_012"
        )

      assert is_binary(response)
    end
  end
end
