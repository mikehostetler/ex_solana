defmodule JidoTest.ErrorTest do
  use ExUnit.Case

  describe "Jido.Error" do
    test "error classes are defined" do
      assert Code.ensure_loaded?(Jido.Error.Invalid)
      assert Code.ensure_loaded?(Jido.Error.Discovery)
      assert Code.ensure_loaded?(Jido.Error.Framework)
      assert Code.ensure_loaded?(Jido.Error.Unknown)
    end
  end

  describe "Jido.Error.Discovery.CacheInitFailed" do
    test "can create exception with reason" do
      error = Jido.Error.Discovery.CacheInitFailed.exception(reason: :oops)

      assert %Jido.Error.Discovery.CacheInitFailed{} = error
      assert error.reason == :oops
    end

    test "produces proper message" do
      error = Jido.Error.Discovery.CacheInitFailed.exception(reason: :some_error)
      message = Exception.message(error)

      assert message =~ "Failed to initialize discovery cache"
      assert message =~ ":some_error"
    end
  end

  describe "Jido.Error.Discovery.CacheRefreshFailed" do
    test "can create exception with reason" do
      error = Jido.Error.Discovery.CacheRefreshFailed.exception(reason: :refresh_problem)

      assert %Jido.Error.Discovery.CacheRefreshFailed{} = error
      assert error.reason == :refresh_problem
    end

    test "produces proper message" do
      error = Jido.Error.Discovery.CacheRefreshFailed.exception(reason: :timeout)
      message = Exception.message(error)

      assert message =~ "Failed to refresh discovery cache"
      assert message =~ ":timeout"
    end
  end

  describe "Jido.Error.Discovery.NotInitialized" do
    test "can create exception" do
      error = Jido.Error.Discovery.NotInitialized.exception([])

      assert %Jido.Error.Discovery.NotInitialized{} = error
    end

    test "produces proper message" do
      error = Jido.Error.Discovery.NotInitialized.exception([])
      message = Exception.message(error)

      assert message =~ "Discovery cache has not been initialized"
      assert message =~ "Jido.Discovery.init/0"
    end
  end

  describe "Jido.Error.Unknown.Unknown" do
    test "can create exception with error value" do
      error = Jido.Error.Unknown.Unknown.exception(error: "something went wrong")

      assert %Jido.Error.Unknown.Unknown{} = error
      assert error.error == "something went wrong"
    end

    test "produces proper message for binary error" do
      error = Jido.Error.Unknown.Unknown.exception(error: "something went wrong")
      message = Exception.message(error)

      assert message == "something went wrong"
    end

    test "produces proper message for non-binary error" do
      error = Jido.Error.Unknown.Unknown.exception(error: {:unexpected, :value})
      message = Exception.message(error)

      assert message == "{:unexpected, :value}"
    end
  end

  describe "Splode integration" do
    test "to_error/1 converts arbitrary values to errors" do
      error = Jido.Error.to_error("something bad")

      assert %Jido.Error.Unknown.Unknown{} = error
    end

    test "to_class/1 aggregates discovery errors" do
      e1 = Jido.Error.Discovery.CacheInitFailed.exception(reason: :a)
      e2 = Jido.Error.Discovery.CacheRefreshFailed.exception(reason: :b)

      class = Jido.Error.to_class([e1, e2])

      assert %Jido.Error.Discovery{} = class
      assert length(class.errors) == 2
    end

    test "unwrap!/1 returns value for ok tuple" do
      result = {:ok, :success}
      assert :success = Jido.Error.unwrap!(result)
    end

    test "unwrap!/1 raises for error tuple" do
      error = Jido.Error.Discovery.NotInitialized.exception([])
      result = {:error, error}

      assert_raise Jido.Error.Discovery.NotInitialized, fn ->
        Jido.Error.unwrap!(result)
      end
    end
  end
end
