defmodule JidoFlame.Case do
  @moduledoc "Base test case for JidoFlame tests"
  use ExUnit.CaseTemplate

  using do
    quote do
      import JidoFlame.Case
    end
  end

  setup _tags do
    :ok
  end
end
