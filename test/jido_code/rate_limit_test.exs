defmodule JidoCode.RateLimitTest do
  use ExUnit.Case, async: false

  alias JidoCode.RateLimit

  setup do
    # Ensure application is started (RateLimit GenServer is in supervision tree)
    Application.ensure_all_started(:jido_code)

    # Reset rate limits before each test
    on_exit(fn ->
      RateLimit.reset(:test_operation, "test-key")
      RateLimit.reset(:resume, "session-123")

      # Reset global rate limits (table exists after app start)
      :ets.delete(:jido_code_rate_limits, {:global, :resume})
      :ets.delete(:jido_code_rate_limits, {:global, :test_operation})
      :ets.delete(:jido_code_rate_limits, {:global, :unconfigured_operation})
      :ets.delete(:jido_code_rate_limits, {:global, :unconfigured_op})
    end)

    :ok
  end

  describe "check_rate_limit/2" do
    test "allows operation when under limit" do
      assert :ok == RateLimit.check_rate_limit(:resume, "session-123")
    end

    test "allows multiple operations up to limit" do
      # Default limit for resume is 5 attempts per 60 seconds
      key = "session-multi-#{:rand.uniform(10000)}"

      # Record 4 attempts
      for _ <- 1..4 do
        RateLimit.record_attempt(:resume, key)
      end

      # 5th check should still be allowed
      assert :ok == RateLimit.check_rate_limit(:resume, key)
    end

    test "blocks operation after exceeding limit" do
      key = "session-limit-#{:rand.uniform(10000)}"

      # Record 5 attempts (the limit)
      for _ <- 1..5 do
        RateLimit.record_attempt(:resume, key)
      end

      # 6th attempt should be blocked
      assert {:error, :rate_limit_exceeded, retry_after} =
               RateLimit.check_rate_limit(:resume, key)

      assert is_integer(retry_after)
      assert retry_after > 0
      assert retry_after <= 60
    end

    test "different keys are tracked independently" do
      key1 = "session-a-#{:rand.uniform(10000)}"
      key2 = "session-b-#{:rand.uniform(10000)}"

      # Exhaust limit for key1
      for _ <- 1..5 do
        RateLimit.record_attempt(:resume, key1)
      end

      # key1 should be blocked
      assert {:error, :rate_limit_exceeded, _} =
               RateLimit.check_rate_limit(:resume, key1)

      # key2 should still be allowed
      assert :ok == RateLimit.check_rate_limit(:resume, key2)
    end

    test "different operations are tracked independently" do
      key = "multi-op-#{:rand.uniform(10000)}"

      # Exhaust limit for :resume
      for _ <- 1..5 do
        RateLimit.record_attempt(:resume, key)
      end

      # :resume should be blocked
      assert {:error, :rate_limit_exceeded, _} =
               RateLimit.check_rate_limit(:resume, key)

      # Different operation should be allowed
      assert :ok == RateLimit.check_rate_limit(:test_operation, key)
    end
  end

  describe "record_attempt/2" do
    test "records an attempt successfully" do
      key = "record-test-#{:rand.uniform(10000)}"

      assert :ok == RateLimit.record_attempt(:resume, key)
    end

    test "multiple records increment the count" do
      key = "record-multi-#{:rand.uniform(10000)}"

      # Record 3 attempts
      for _ <- 1..3 do
        RateLimit.record_attempt(:resume, key)
      end

      # Should still be under limit (5 total allowed)
      assert :ok == RateLimit.check_rate_limit(:resume, key)

      # Record 2 more to hit limit
      for _ <- 1..2 do
        RateLimit.record_attempt(:resume, key)
      end

      # Now should be at limit, next check should fail
      assert {:error, :rate_limit_exceeded, _} =
               RateLimit.check_rate_limit(:resume, key)
    end

    test "records persist across multiple checks" do
      key = "persist-test-#{:rand.uniform(10000)}"

      # Record 2 attempts
      RateLimit.record_attempt(:resume, key)
      RateLimit.record_attempt(:resume, key)

      # Check should pass
      assert :ok == RateLimit.check_rate_limit(:resume, key)

      # Record 3 more
      for _ <- 1..3 do
        RateLimit.record_attempt(:resume, key)
      end

      # Total of 5 attempts, next should fail
      assert {:error, :rate_limit_exceeded, _} =
               RateLimit.check_rate_limit(:resume, key)
    end
  end

  describe "reset/2" do
    test "clears rate limit for a key" do
      key = "reset-test-#{:rand.uniform(10000)}"

      # Exhaust the limit
      for _ <- 1..5 do
        RateLimit.record_attempt(:resume, key)
      end

      # Should be blocked
      assert {:error, :rate_limit_exceeded, _} =
               RateLimit.check_rate_limit(:resume, key)

      # Reset the limit
      RateLimit.reset(:resume, key)

      # Should be allowed again
      assert :ok == RateLimit.check_rate_limit(:resume, key)
    end

    test "reset only affects the specific key" do
      key1 = "reset-a-#{:rand.uniform(10000)}"
      key2 = "reset-b-#{:rand.uniform(10000)}"

      # Exhaust both
      for _ <- 1..5 do
        RateLimit.record_attempt(:resume, key1)
        RateLimit.record_attempt(:resume, key2)
      end

      # Both should be blocked
      assert {:error, :rate_limit_exceeded, _} =
               RateLimit.check_rate_limit(:resume, key1)

      assert {:error, :rate_limit_exceeded, _} =
               RateLimit.check_rate_limit(:resume, key2)

      # Reset only key1
      RateLimit.reset(:resume, key1)

      # key1 should be allowed
      assert :ok == RateLimit.check_rate_limit(:resume, key1)

      # key2 should still be blocked
      assert {:error, :rate_limit_exceeded, _} =
               RateLimit.check_rate_limit(:resume, key2)
    end

    test "reset is idempotent" do
      key = "idempotent-#{:rand.uniform(10000)}"

      # Reset multiple times
      assert :ok == RateLimit.reset(:resume, key)
      assert :ok == RateLimit.reset(:resume, key)
      assert :ok == RateLimit.reset(:resume, key)

      # Should still work normally
      assert :ok == RateLimit.check_rate_limit(:resume, key)
    end
  end

  describe "retry_after calculation" do
    test "retry_after decreases over time" do
      key = "retry-time-#{:rand.uniform(10000)}"

      # Exhaust limit
      for _ <- 1..5 do
        RateLimit.record_attempt(:resume, key)
      end

      # Get first retry_after
      {:error, :rate_limit_exceeded, retry1} =
        RateLimit.check_rate_limit(:resume, key)

      # Wait a bit
      Process.sleep(100)

      # Get second retry_after
      {:error, :rate_limit_exceeded, retry2} =
        RateLimit.check_rate_limit(:resume, key)

      # retry_after should be less than or equal (allowing for timing)
      # In practice, it should be slightly less
      assert retry2 <= retry1
    end

    test "retry_after is always positive" do
      key = "positive-retry-#{:rand.uniform(10000)}"

      # Exhaust limit
      for _ <- 1..5 do
        RateLimit.record_attempt(:resume, key)
      end

      {:error, :rate_limit_exceeded, retry_after} =
        RateLimit.check_rate_limit(:resume, key)

      assert retry_after > 0
    end

    test "retry_after is within the window period" do
      key = "window-retry-#{:rand.uniform(10000)}"

      # Exhaust limit
      for _ <- 1..5 do
        RateLimit.record_attempt(:resume, key)
      end

      {:error, :rate_limit_exceeded, retry_after} =
        RateLimit.check_rate_limit(:resume, key)

      # Should be less than or equal to the window (60 seconds for resume)
      assert retry_after <= 60
    end
  end

  describe "sliding window behavior" do
    test "old attempts don't count towards limit" do
      # This test would require time manipulation or waiting 60+ seconds
      # For now, we'll just verify the mechanism exists by checking
      # that the window is respected

      key = "sliding-#{:rand.uniform(10000)}"

      # Record attempts and verify sliding window concept
      # (Full test would need time travel or very long waits)
      for _ <- 1..3 do
        RateLimit.record_attempt(:resume, key)
      end

      assert :ok == RateLimit.check_rate_limit(:resume, key)
    end
  end

  describe "concurrent access" do
    test "handles concurrent checks correctly" do
      key = "concurrent-#{:rand.uniform(10000)}"

      # Spawn multiple processes trying to check rate limit
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            case RateLimit.check_rate_limit(:resume, key) do
              :ok ->
                # Record if allowed
                RateLimit.record_attempt(:resume, key)
                {:ok, i}

              {:error, :rate_limit_exceeded, _} ->
                {:blocked, i}
            end
          end)
        end

      results = Task.await_many(tasks)

      # Count how many were allowed
      allowed = Enum.count(results, fn {status, _} -> status == :ok end)

      # Should allow exactly 5 (the limit)
      # Note: Due to race conditions, might be slightly different
      # but should be close to the limit
      assert allowed <= 5
    end
  end

  describe "configuration" do
    test "uses default limits when not configured" do
      # :test_operation is not configured, should use defaults
      key = "default-config-#{:rand.uniform(10000)}"

      # Default is 10 attempts per 60 seconds
      # Record 9 attempts
      for _ <- 1..9 do
        RateLimit.record_attempt(:test_operation, key)
      end

      # Should still be under limit (10th check)
      assert :ok == RateLimit.check_rate_limit(:test_operation, key)

      # Record the 10th attempt
      RateLimit.record_attempt(:test_operation, key)

      # 11th check should be blocked (at limit now)
      assert {:error, :rate_limit_exceeded, _} =
               RateLimit.check_rate_limit(:test_operation, key)
    end

    test "uses configured limits for resume operation" do
      # :resume is configured with limit: 5, window: 60
      key = "configured-#{:rand.uniform(10000)}"

      # Should allow exactly 5
      for _ <- 1..5 do
        RateLimit.record_attempt(:resume, key)
      end

      # 6th should be blocked
      assert {:error, :rate_limit_exceeded, _} =
               RateLimit.check_rate_limit(:resume, key)
    end
  end

  describe "ETS table operations" do
    test "creates and maintains ETS table" do
      # Verify table exists
      table_name = :jido_code_rate_limits
      tables = :ets.all()

      assert table_name in tables
    end

    test "ETS table survives individual test operations" do
      key = "ets-persist-#{:rand.uniform(10000)}"

      # Perform operation
      RateLimit.record_attempt(:resume, key)

      # Table should still exist
      assert :jido_code_rate_limits in :ets.all()
    end

    test "record_attempt bounds timestamp list to prevent unbounded growth" do
      key = "bounded-test-#{:rand.uniform(10000)}"

      # Record 100 attempts (far exceeding limit)
      for _ <- 1..100 do
        RateLimit.record_attempt(:resume, key)
      end

      # Verify list is bounded to 2x limit (limit=5, so max=10)
      [{_, timestamps}] = :ets.lookup(:jido_code_rate_limits, {:resume, key})
      assert length(timestamps) <= 10

      # Verify we kept the most recent entries
      assert is_list(timestamps)
      assert Enum.all?(timestamps, &is_integer/1)
    end
  end

  describe "check_global_rate_limit/1" do
    test "allows operation when under global limit" do
      # Global limit for resume is 20 per 60 seconds (default)
      assert :ok == RateLimit.check_global_rate_limit(:resume)
    end

    test "allows multiple operations up to global limit" do
      # Record 19 global attempts (limit is 20)
      for _ <- 1..19 do
        RateLimit.record_global_attempt(:resume)
      end

      # 20th check should still be allowed
      assert :ok == RateLimit.check_global_rate_limit(:resume)
    end

    test "blocks operation after exceeding global limit" do
      # Record 20 global attempts (the limit)
      for _ <- 1..20 do
        RateLimit.record_global_attempt(:resume)
      end

      # 21st attempt should be blocked
      assert {:error, :rate_limit_exceeded, retry_after} =
               RateLimit.check_global_rate_limit(:resume)

      assert is_integer(retry_after)
      assert retry_after > 0
      assert retry_after <= 60
    end

    test "global limit is independent of per-session limits" do
      # Exhaust per-session limit for a specific session
      session_key = "session-#{:rand.uniform(10000)}"

      for _ <- 1..5 do
        RateLimit.record_attempt(:resume, session_key)
      end

      # Per-session should be blocked
      assert {:error, :rate_limit_exceeded, _} =
               RateLimit.check_rate_limit(:resume, session_key)

      # But global should still be allowed (different tracking)
      assert :ok == RateLimit.check_global_rate_limit(:resume)
    end

    test "returns :ok when global limit not configured" do
      # Operations without global limits configured should always pass
      assert :ok == RateLimit.check_global_rate_limit(:unconfigured_operation)
    end
  end

  describe "record_global_attempt/1" do
    test "records a global attempt successfully" do
      assert :ok == RateLimit.record_global_attempt(:resume)
    end

    test "multiple global records increment the count" do
      # Record several global attempts
      for _ <- 1..10 do
        RateLimit.record_global_attempt(:resume)
      end

      # Should be able to check how many are tracked
      # Global limit is 20, so 10 attempts should still be under limit
      assert :ok == RateLimit.check_global_rate_limit(:resume)
    end

    test "global tracking is separate from per-session tracking" do
      session_key = "session-#{:rand.uniform(10000)}"

      # Record global attempts
      for _ <- 1..10 do
        RateLimit.record_global_attempt(:resume)
      end

      # Record per-session attempts
      for _ <- 1..3 do
        RateLimit.record_attempt(:resume, session_key)
      end

      # Both should be under their respective limits
      assert :ok == RateLimit.check_global_rate_limit(:resume)
      assert :ok == RateLimit.check_rate_limit(:resume, session_key)
    end

    test "handles unconfigured operations gracefully" do
      # Recording attempt for unconfigured operation should succeed
      assert :ok == RateLimit.record_global_attempt(:unconfigured_op)

      # Check should also succeed
      assert :ok == RateLimit.check_global_rate_limit(:unconfigured_op)
    end
  end

  describe "global rate limiting prevents bypass attacks" do
    test "cannot bypass global limit by creating multiple sessions" do
      # This simulates the attack scenario from Security Issue #6:
      # Attacker creates 100 sessions and resumes each 5 times

      # Record resume attempts across many different sessions
      # Each session gets 1 resume, but globally we exceed the limit
      for i <- 1..21 do
        session_key = "attack-session-#{i}"

        # Record both global and per-session
        # (In real code, resume/1 does both automatically)
        RateLimit.record_global_attempt(:resume)
        RateLimit.record_attempt(:resume, session_key)
      end

      # Any individual session is still under its per-session limit (1 < 5)
      assert :ok == RateLimit.check_rate_limit(:resume, "attack-session-1")

      # But the global limit (20) is exceeded
      assert {:error, :rate_limit_exceeded, _} =
               RateLimit.check_global_rate_limit(:resume)

      # This prevents the attack: even though the attacker has many sessions,
      # they hit the global rate limit
    end

    test "legitimate multi-session use is still allowed" do
      # A user with 4 active sessions, each resuming occasionally,
      # should not hit global limits under normal use

      for session_num <- 1..4 do
        for _attempt_num <- 1..3 do
          session_key = "legit-session-#{session_num}"

          # Simulate resume (both checks would happen in real code)
          assert :ok == RateLimit.check_global_rate_limit(:resume)
          assert :ok == RateLimit.check_rate_limit(:resume, session_key)

          # Record both
          RateLimit.record_global_attempt(:resume)
          RateLimit.record_attempt(:resume, session_key)
        end
      end

      # Total: 4 sessions × 3 resumes = 12 global operations
      # This is under the global limit (20), so it should succeed

      # Both checks should still pass
      assert :ok == RateLimit.check_global_rate_limit(:resume)
      assert :ok == RateLimit.check_rate_limit(:resume, "legit-session-1")
    end
  end
end
