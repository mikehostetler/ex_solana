defmodule KaizenTest do
  use ExUnit.Case
  doctest Kaizen

  test "greets the world" do
    assert Kaizen.version() != nil
  end
end
