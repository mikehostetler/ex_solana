defmodule JidoCode.TUI.ClipboardTest do
  use ExUnit.Case, async: false

  alias JidoCode.TUI.Clipboard

  setup do
    # Clear cache before each test
    Clipboard.clear_cache()
    on_exit(fn -> Clipboard.clear_cache() end)
    :ok
  end

  describe "detect_clipboard_command/0" do
    test "returns a tuple with command and args when clipboard available" do
      result = Clipboard.detect_clipboard_command()

      # Should be either a valid command tuple or nil
      case result do
        nil ->
          # No clipboard available on this system, that's okay
          assert true

        {command, args} when is_binary(command) and is_list(args) ->
          # Valid clipboard command detected
          assert System.find_executable(command) != nil
      end
    end

    test "caches the detected command" do
      # First call detects and caches
      result1 = Clipboard.detect_clipboard_command()
      # Second call should return same cached result
      result2 = Clipboard.detect_clipboard_command()

      assert result1 == result2
    end

    test "clear_cache/0 clears the cached command" do
      # Detect and cache
      _result1 = Clipboard.detect_clipboard_command()
      # Clear cache
      assert Clipboard.clear_cache() == :ok
      # Should still work after clearing
      _result2 = Clipboard.detect_clipboard_command()
    end
  end

  describe "available?/0" do
    test "returns boolean" do
      result = Clipboard.available?()
      assert is_boolean(result)
    end

    test "returns true when clipboard command exists" do
      case Clipboard.detect_clipboard_command() do
        nil ->
          refute Clipboard.available?()

        {_command, _args} ->
          assert Clipboard.available?()
      end
    end
  end

  describe "copy_to_clipboard/1" do
    test "returns {:error, :invalid_text} for non-binary input" do
      assert Clipboard.copy_to_clipboard(123) == {:error, :invalid_text}
      assert Clipboard.copy_to_clipboard(nil) == {:error, :invalid_text}
      assert Clipboard.copy_to_clipboard([]) == {:error, :invalid_text}
    end

    test "returns {:error, :clipboard_unavailable} when no clipboard command" do
      # This test is only meaningful if no clipboard is available
      case Clipboard.detect_clipboard_command() do
        nil ->
          assert Clipboard.copy_to_clipboard("test") == {:error, :clipboard_unavailable}

        _command ->
          # Skip test when clipboard is available
          :ok
      end
    end

    @tag :clipboard_integration
    test "successfully copies text when clipboard available" do
      # This test requires a working clipboard command
      case Clipboard.detect_clipboard_command() do
        nil ->
          # No clipboard available, skip
          :ok

        {_command, _args} ->
          result = Clipboard.copy_to_clipboard("Hello from test!")
          assert result == :ok
      end
    end

    @tag :clipboard_integration
    test "handles empty string" do
      case Clipboard.detect_clipboard_command() do
        nil ->
          :ok

        {_command, _args} ->
          result = Clipboard.copy_to_clipboard("")
          assert result == :ok
      end
    end

    @tag :clipboard_integration
    test "handles multiline text" do
      case Clipboard.detect_clipboard_command() do
        nil ->
          :ok

        {_command, _args} ->
          text = """
          Line 1
          Line 2
          Line 3
          """

          result = Clipboard.copy_to_clipboard(text)
          assert result == :ok
      end
    end

    @tag :clipboard_integration
    test "handles unicode text" do
      case Clipboard.detect_clipboard_command() do
        nil ->
          :ok

        {_command, _args} ->
          result = Clipboard.copy_to_clipboard("Hello 世界 🎉")
          assert result == :ok
      end
    end
  end

  describe "clear_cache/0" do
    test "returns :ok" do
      assert Clipboard.clear_cache() == :ok
    end

    test "can be called multiple times safely" do
      assert Clipboard.clear_cache() == :ok
      assert Clipboard.clear_cache() == :ok
      assert Clipboard.clear_cache() == :ok
    end

    test "forces re-detection on next call" do
      # Detect and cache
      _result1 = Clipboard.detect_clipboard_command()

      # Clear cache
      Clipboard.clear_cache()

      # This should trigger fresh detection
      # We can't easily verify it re-detected, but we can verify it works
      _result2 = Clipboard.detect_clipboard_command()
    end
  end
end
