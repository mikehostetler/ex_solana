defmodule JidoMessagingTest do
  use ExUnit.Case
  doctest JidoMessaging

  describe "jido_messaging" do
    test "module exists and can be called" do
      assert is_atom(JidoMessaging)
    end
  end
end
