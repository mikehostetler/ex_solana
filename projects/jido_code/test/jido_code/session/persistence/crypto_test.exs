defmodule JidoCode.Session.Persistence.CryptoTest do
  use ExUnit.Case, async: true

  alias JidoCode.Session.Persistence.Crypto

  describe "compute_signature/1" do
    test "generates a valid Base64 signature for JSON string" do
      json = Jason.encode!(%{"test" => "data"})
      signature = Crypto.compute_signature(json)

      assert is_binary(signature)
      assert String.length(signature) > 0
      # HMAC-SHA256 produces 32 bytes, Base64 encoded = 44 chars
      assert String.length(signature) == 44
      # Should end with = (Base64 padding)
      assert String.ends_with?(signature, "=")
    end

    test "produces deterministic signatures for same input" do
      json = Jason.encode!(%{"test" => "data"})
      sig1 = Crypto.compute_signature(json)
      sig2 = Crypto.compute_signature(json)

      assert sig1 == sig2
    end

    test "produces different signatures for different inputs" do
      json1 = Jason.encode!(%{"test" => "data1"})
      json2 = Jason.encode!(%{"test" => "data2"})

      sig1 = Crypto.compute_signature(json1)
      sig2 = Crypto.compute_signature(json2)

      assert sig1 != sig2
    end

    test "handles empty JSON object" do
      json = Jason.encode!(%{})
      signature = Crypto.compute_signature(json)

      assert is_binary(signature)
      assert String.length(signature) == 44
    end

    test "handles large JSON strings" do
      large_data = %{"data" => String.duplicate("x", 10_000)}
      json = Jason.encode!(large_data)
      signature = Crypto.compute_signature(json)

      assert is_binary(signature)
      assert String.length(signature) == 44
    end
  end

  describe "verify_signature/2" do
    test "verifies a valid signature successfully" do
      json = Jason.encode!(%{"test" => "data"})
      signature = Crypto.compute_signature(json)

      assert :ok == Crypto.verify_signature(json, signature)
    end

    test "rejects invalid signature" do
      json = Jason.encode!(%{"test" => "data"})
      invalid_signature = "invalid_signature_base64_encoded_string="

      assert {:error, :signature_verification_failed} ==
               Crypto.verify_signature(json, invalid_signature)
    end

    test "rejects signature for different data" do
      json1 = Jason.encode!(%{"test" => "data1"})
      json2 = Jason.encode!(%{"test" => "data2"})

      signature1 = Crypto.compute_signature(json1)

      assert {:error, :signature_verification_failed} ==
               Crypto.verify_signature(json2, signature1)
    end

    test "rejects tampered data with original signature" do
      original = %{"amount" => 100, "user" => "alice"}
      json = Jason.encode!(original)
      signature = Crypto.compute_signature(json)

      # Tamper with the data
      tampered = %{"amount" => 1000, "user" => "alice"}
      tampered_json = Jason.encode!(tampered)

      assert {:error, :signature_verification_failed} ==
               Crypto.verify_signature(tampered_json, signature)
    end

    test "signature verification is case-sensitive" do
      json = Jason.encode!(%{"test" => "data"})
      signature = Crypto.compute_signature(json)
      uppercase_sig = String.upcase(signature)

      assert {:error, :signature_verification_failed} ==
               Crypto.verify_signature(json, uppercase_sig)
    end

    test "handles whitespace differences in JSON" do
      # Compact JSON
      json1 = Jason.encode!(%{"test" => "data"})
      sig1 = Crypto.compute_signature(json1)

      # Pretty JSON (different whitespace)
      json2 = Jason.encode!(%{"test" => "data"}, pretty: true)
      sig2 = Crypto.compute_signature(json2)

      # Signatures should be different because JSON strings are different
      assert sig1 != sig2
      assert :ok == Crypto.verify_signature(json1, sig1)
      assert :ok == Crypto.verify_signature(json2, sig2)
      # Cross-verification should fail
      assert {:error, :signature_verification_failed} ==
               Crypto.verify_signature(json1, sig2)
    end
  end

  describe "signed?/1" do
    test "returns true for map with signature field" do
      payload = %{"data" => "test", "signature" => "abc123"}
      assert Crypto.signed?(payload) == true
    end

    test "returns false for map without signature field" do
      payload = %{"data" => "test"}
      assert Crypto.signed?(payload) == false
    end

    test "returns false for empty map" do
      assert Crypto.signed?(%{}) == false
    end

    test "handles string keys vs atom keys" do
      with_string_key = %{"signature" => "abc"}
      with_atom_key = %{signature: "abc"}

      assert Crypto.signed?(with_string_key) == true
      # signed? checks for string key "signature"
      assert Crypto.signed?(with_atom_key) == false
    end
  end

  describe "round-trip signing and verification" do
    test "sign and verify a session-like payload" do
      session = %{
        "id" => "123",
        "name" => "Test Session",
        "project_path" => "/tmp/test",
        "version" => 1,
        "created_at" => "2024-01-01T10:00:00Z"
      }

      # Encode to JSON
      json = Jason.encode!(session)

      # Sign
      signature = Crypto.compute_signature(json)

      # Verify
      assert :ok == Crypto.verify_signature(json, signature)
    end

    test "sign, modify, and fail verification" do
      session = %{
        "id" => "123",
        "name" => "Test Session",
        "admin" => false
      }

      json = Jason.encode!(session)
      signature = Crypto.compute_signature(json)

      # Tamper: change admin flag
      tampered = %{session | "admin" => true}
      tampered_json = Jason.encode!(tampered)

      # Verification should fail
      assert {:error, :signature_verification_failed} ==
               Crypto.verify_signature(tampered_json, signature)
    end

    test "multiple rounds of signing produce same signature" do
      data = %{"counter" => 1}
      json = Jason.encode!(data)

      signatures =
        Enum.map(1..100, fn _ ->
          Crypto.compute_signature(json)
        end)

      # All signatures should be identical
      assert Enum.uniq(signatures) |> length() == 1
    end
  end

  describe "constant-time comparison (timing attack resistance)" do
    test "verification time should not leak information about signature" do
      json = Jason.encode!(%{"data" => "test"})
      correct_sig = Crypto.compute_signature(json)

      # Create signatures that differ in first, middle, and last character
      wrong_sig_first = String.replace_prefix(correct_sig, String.at(correct_sig, 0), "X")

      wrong_sig_middle =
        String.slice(correct_sig, 0, 20) <>
          "X" <> String.slice(correct_sig, 21..-1)

      wrong_sig_last = String.replace_suffix(correct_sig, String.at(correct_sig, -1), "X")

      # All wrong signatures should fail verification
      assert {:error, :signature_verification_failed} ==
               Crypto.verify_signature(json, wrong_sig_first)

      assert {:error, :signature_verification_failed} ==
               Crypto.verify_signature(json, wrong_sig_middle)

      assert {:error, :signature_verification_failed} ==
               Crypto.verify_signature(json, wrong_sig_last)

      # Note: We can't easily test timing in unit tests, but the implementation
      # uses constant-time comparison (XOR + OR operations)
    end

    test "different length signatures are rejected immediately" do
      json = Jason.encode!(%{"data" => "test"})
      correct_sig = Crypto.compute_signature(json)
      short_sig = String.slice(correct_sig, 0, 20)

      assert {:error, :signature_verification_failed} ==
               Crypto.verify_signature(json, short_sig)
    end
  end

  describe "edge cases" do
    test "handles JSON with special characters" do
      data = %{
        "text" => "Special chars: \n\t\r\"\\",
        "unicode" => "Hello 世界 🌍",
        "emoji" => "✅ 🔒 🎉"
      }

      json = Jason.encode!(data)
      signature = Crypto.compute_signature(json)

      assert :ok == Crypto.verify_signature(json, signature)
    end

    test "handles deeply nested JSON" do
      nested = %{
        "level1" => %{
          "level2" => %{
            "level3" => %{
              "level4" => "deep value"
            }
          }
        }
      }

      json = Jason.encode!(nested)
      signature = Crypto.compute_signature(json)

      assert :ok == Crypto.verify_signature(json, signature)
    end

    test "handles JSON with null values" do
      data = %{"key" => nil}
      json = Jason.encode!(data)
      signature = Crypto.compute_signature(json)

      assert :ok == Crypto.verify_signature(json, signature)
    end

    test "handles JSON arrays" do
      data = %{"items" => [1, 2, 3, 4, 5]}
      json = Jason.encode!(data)
      signature = Crypto.compute_signature(json)

      assert :ok == Crypto.verify_signature(json, signature)
    end
  end

  describe "signing key caching" do
    test "signing key is cached and reused" do
      # Clear cache to start fresh
      Crypto.invalidate_key_cache()

      # First computation - derive key
      json1 = Jason.encode!(%{test: "data1"})
      sig1 = Crypto.compute_signature(json1)

      # Second computation - should use cached key
      json2 = Jason.encode!(%{test: "data2"})
      sig2 = Crypto.compute_signature(json2)

      # Both signatures should verify (key is consistent)
      assert :ok == Crypto.verify_signature(json1, sig1)
      assert :ok == Crypto.verify_signature(json2, sig2)
    end

    test "invalidate_key_cache clears the cache" do
      # Create a signature with cached key
      json = Jason.encode!(%{test: "data"})
      sig1 = Crypto.compute_signature(json)

      # Invalidate cache
      Crypto.invalidate_key_cache()

      # Create another signature (should re-derive key)
      sig2 = Crypto.compute_signature(json)

      # Signatures should be identical (same key derivation)
      assert sig1 == sig2
    end

    test "caching provides performance benefit" do
      # Clear cache
      Crypto.invalidate_key_cache()

      json = Jason.encode!(%{test: "perf"})

      # Measure first call (cold cache)
      {time1, _sig1} = :timer.tc(fn -> Crypto.compute_signature(json) end)

      # Measure second call (warm cache)
      {time2, _sig2} = :timer.tc(fn -> Crypto.compute_signature(json) end)

      # Second call should be significantly faster (at least 2x)
      # PBKDF2 with 100k iterations is expensive
      assert time2 < time1 / 2, "Cached call should be at least 2x faster"
    end
  end
end
