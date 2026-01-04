defmodule JidoSandboxTest do
  use ExUnit.Case
  doctest JidoSandbox

  test "greets the world" do
    assert JidoSandbox.hello() == :world
  end
end
