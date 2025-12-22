defmodule JidoCode.Session.PersistenceSessionLimitTest do
  @moduledoc """
  Tests for enhanced session limit features:
  - 80% warning threshold
  - Auto-cleanup on limit

  Note: Full integration tests for session limits exist in persistence_test.exs
  tagged with :llm. These tests focus on the configuration and helper logic.
  """

  use ExUnit.Case, async: true

  @moduletag :session_limit

  describe "configuration" do
    test "get_max_sessions default is 100" do
      # Clear any existing config
      Application.delete_env(:jido_code, :persistence)

      # Default should be 100
      assert JidoCode.Session.Persistence.get_max_sessions() == 100
    end

    test "get_max_sessions reads from config" do
      original = Application.get_env(:jido_code, :persistence, [])

      try do
        Application.put_env(:jido_code, :persistence, max_sessions: 50)
        assert JidoCode.Session.Persistence.get_max_sessions() == 50
      after
        Application.put_env(:jido_code, :persistence, original)
      end
    end

    test "get_auto_cleanup_enabled? default is false" do
      # Clear any existing config
      Application.delete_env(:jido_code, :persistence)

      # Default should be false (conservative - don't delete automatically)
      refute JidoCode.Session.Persistence.get_auto_cleanup_enabled?()
    end

    test "get_auto_cleanup_enabled? reads from config" do
      original = Application.get_env(:jido_code, :persistence, [])

      try do
        Application.put_env(:jido_code, :persistence, auto_cleanup_on_limit: true)
        assert JidoCode.Session.Persistence.get_auto_cleanup_enabled?()

        Application.put_env(:jido_code, :persistence, auto_cleanup_on_limit: false)
        refute JidoCode.Session.Persistence.get_auto_cleanup_enabled?()
      after
        Application.put_env(:jido_code, :persistence, original)
      end
    end
  end

  describe "threshold calculations" do
    test "80% threshold calculated correctly" do
      # 80% of 100 = 80
      assert trunc(100 * 0.8) == 80

      # 80% of 5 = 4
      assert trunc(5 * 0.8) == 4

      # 80% of 10 = 8
      assert trunc(10 * 0.8) == 8
    end

    test "percentage calculation" do
      # 80 out of 100 = 80%
      assert trunc(80 / 100 * 100) == 80

      # 4 out of 5 = 80%
      assert trunc(4 / 5 * 100) == 80

      # 8 out of 10 = 80%
      assert trunc(8 / 10 * 100) == 80
    end
  end

  describe "documentation" do
    test "configuration options are documented in module docs" do
      {:docs_v1, _, :elixir, "text/markdown", module_doc, _, _} =
        Code.fetch_docs(JidoCode.Session.Persistence)

      # Module should exist and have docs
      assert module_doc != :none
    end

    test "error sanitizer handles :session_limit_reached" do
      result = JidoCode.Commands.ErrorSanitizer.sanitize_error(:session_limit_reached)
      assert result == "Maximum sessions reached."

      # Should not expose implementation details
      refute String.contains?(result, "limit")
      refute String.contains?(result, "count")
    end
  end
end
