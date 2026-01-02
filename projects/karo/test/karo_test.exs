defmodule KaroTest do
  use ExUnit.Case
  doctest Karo

  test "greets the world" do
    assert Karo.hello() == :world
  end
end
