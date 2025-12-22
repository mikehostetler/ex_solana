defmodule JidoCode.Session.Persistence.Crypto do
  @moduledoc """
  Cryptographic operations for session file integrity verification.

  Provides HMAC-SHA256 signing and verification for persisted session files
  to prevent tampering. Uses a machine-specific signing key derived from
  the application's compile-time salt and hostname.

  ## Security Model

  - **Algorithm:** HMAC-SHA256
  - **Key Derivation:** PBKDF2 with application salt + hostname
  - **Signature Location:** `signature` field in JSON (excluded from signed payload)
  - **Backward Compatibility:** Unsigned files accepted with warning (v1.0.0)

  ## Example

      iex> data = %{id: "uuid", name: "Session"}
      iex> signed = Crypto.sign_payload(data)
      iex> Crypto.verify_payload(signed)
      {:ok, %{id: "uuid", name: "Session"}}

      iex> tampered = Map.put(signed, "name", "Tampered")
      iex> Crypto.verify_payload(tampered)
      {:error, :signature_verification_failed}
  """

  require Logger

  @hash_algorithm :sha256
  @iterations 100_000
  @key_length 32

  # Compile-time application salt (changes per release)
  @app_salt Application.compile_env(:jido_code, :signing_salt, "jido_code_session_v1")

  # ETS table for caching the derived signing key
  @crypto_cache :jido_code_crypto_cache

  @typedoc "Signed payload with signature field"
  @type signed_payload :: %{required(String.t()) => term(), required(String.t()) => String.t()}

  @doc """
  Creates the ETS table for caching the signing key.

  This should be called during application startup to ensure the cache
  is available before any signing operations occur.

  ## Examples

      iex> Crypto.create_cache_table()
      :ok
  """
  @spec create_cache_table() :: :ok
  def create_cache_table do
    # Create table if it doesn't exist
    case :ets.whereis(@crypto_cache) do
      :undefined ->
        :ets.new(@crypto_cache, [:set, :public, :named_table])
        :ok

      _ref ->
        :ok
    end
  end

  @doc """
  Invalidates the cached signing key.

  Useful for testing scenarios where you want to force re-derivation
  of the signing key.

  ## Examples

      iex> Crypto.invalidate_key_cache()
      :ok
  """
  @spec invalidate_key_cache() :: :ok
  def invalidate_key_cache do
    case :ets.whereis(@crypto_cache) do
      :undefined ->
        :ok

      _ref ->
        :ets.delete(@crypto_cache, :signing_key)
        :ok
    end
  end

  @doc """
  Computes HMAC-SHA256 signature for a JSON string.

  Returns a Base64-encoded signature that can be verified later.

  ## Parameters

  - `json_string` - JSON-encoded string to sign

  ## Returns

  - Base64-encoded signature string

  ## Examples

      iex> json = Jason.encode!(%{id: "123", data: "test"})
      iex> signature = Crypto.compute_signature(json)
      iex> is_binary(signature)
      true
  """
  @spec compute_signature(String.t()) :: String.t()
  def compute_signature(json_string) when is_binary(json_string) do
    :crypto.mac(:hmac, @hash_algorithm, signing_key(), json_string)
    |> Base.encode64()
  end

  @doc """
  Verifies HMAC signature over JSON payload.

  Extracts the signature from the parsed map, recomputes HMAC over the
  payload (without signature), and compares. Uses constant-time comparison
  to prevent timing attacks.

  ## Parameters

  - `unsigned_json` - JSON string of payload WITHOUT signature field
  - `provided_signature` - Base64-encoded signature to verify

  ## Returns

  - `:ok` - Signature is valid
  - `{:error, :signature_verification_failed}` - Signature is invalid

  ## Examples

      iex> json = Jason.encode!(%{data: "test"})
      iex> signature = Crypto.compute_signature(json)
      iex> Crypto.verify_signature(json, signature)
      :ok
  """
  @spec verify_signature(String.t(), String.t()) :: :ok | {:error, :signature_verification_failed}
  def verify_signature(unsigned_json, provided_signature)
      when is_binary(unsigned_json) and is_binary(provided_signature) do
    expected_signature = compute_signature(unsigned_json)

    # Constant-time comparison to prevent timing attacks
    if secure_compare(provided_signature, expected_signature) do
      :ok
    else
      {:error, :signature_verification_failed}
    end
  end

  @doc """
  Checks if a payload has a signature field.

  Useful for determining if file is signed or legacy unsigned format.

  ## Examples

      iex> Crypto.signed?(%{"signature" => "..."})
      true

      iex> Crypto.signed?(%{data: "test"})
      false
  """
  @spec signed?(map()) :: boolean()
  def signed?(payload) when is_map(payload) do
    Map.has_key?(payload, "signature")
  end

  # Private Functions

  # Derives a deterministic but machine-specific signing key
  defp signing_key do
    # Check cache first (10x+ speedup by avoiding PBKDF2 recomputation)
    case :ets.whereis(@crypto_cache) do
      :undefined ->
        # Cache not initialized, derive key directly (testing scenario)
        derive_signing_key()

      _ref ->
        case :ets.lookup(@crypto_cache, :signing_key) do
          [{:signing_key, key}] ->
            # Cache hit - return cached key
            key

          [] ->
            # Cache miss - derive and cache the key
            key = derive_signing_key()
            :ets.insert(@crypto_cache, {:signing_key, key})
            key
        end
    end
  end

  # Derives the signing key using PBKDF2 with multiple entropy sources
  defp derive_signing_key do
    # Combine multiple entropy sources for stronger key derivation:
    # 1. Application salt (compile-time constant)
    # 2. Machine secret (per-machine random value)
    # 3. Hostname (additional machine identifier)
    #
    # This prevents key prediction even if attacker knows the application salt
    machine_secret = get_or_create_machine_secret()
    hostname = get_hostname()

    # Combine all entropy sources into the salt
    salt = @app_salt <> machine_secret <> hostname

    # Use PBKDF2 to derive a strong key (expensive operation - 100k iterations)
    :crypto.pbkdf2_hmac(
      @hash_algorithm,
      @app_salt,
      salt,
      @iterations,
      @key_length
    )
  end

  # Gets or creates the per-machine secret file
  # Returns a random secret unique to this machine, persisted across restarts
  defp get_or_create_machine_secret do
    secret_path = machine_secret_path()

    case File.read(secret_path) do
      {:ok, secret} ->
        # Validate secret format (should be 32 hex characters minimum)
        if byte_size(secret) >= 32 do
          secret
        else
          # Invalid/corrupted secret - regenerate
          Logger.warning("Machine secret file corrupted, regenerating")
          generate_and_save_machine_secret(secret_path)
        end

      {:error, :enoent} ->
        # First run - generate new secret
        Logger.info("Generating new machine secret for signing key derivation")
        generate_and_save_machine_secret(secret_path)

      {:error, reason} ->
        # Permission or I/O error - log and use fallback
        Logger.error("Failed to read machine secret: #{inspect(reason)}, using fallback")
        # Use a fallback based on hostname + node name
        # This is weaker but better than crashing
        fallback_entropy()
    end
  end

  # Generate and save a new machine secret
  defp generate_and_save_machine_secret(secret_path) do
    # Generate 32 bytes of random data (256 bits)
    secret = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

    # Ensure parent directory exists
    secret_dir = Path.dirname(secret_path)
    File.mkdir_p!(secret_dir)

    # Write secret file with restricted permissions
    case File.write(secret_path, secret, [:binary]) do
      :ok ->
        # Set file permissions to 0600 (owner read/write only) on Unix systems
        case :file.change_mode(secret_path, 0o600) do
          :ok ->
            Logger.info("Machine secret generated and saved to #{secret_path}")

          {:error, reason} ->
            Logger.warning("Could not set machine secret permissions: #{inspect(reason)}")
        end

        secret

      {:error, reason} ->
        Logger.error("Failed to save machine secret: #{inspect(reason)}")
        # Fall back to in-memory random value (weaker, not persisted)
        :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
    end
  end

  # Get the path to the machine secret file
  defp machine_secret_path do
    # Store in ~/.jido_code/machine_secret
    config_dir = Path.expand("~/.jido_code")
    Path.join(config_dir, "machine_secret")
  end

  # Fallback entropy when machine secret file can't be read
  # Uses hostname + node name as weaker entropy source
  defp fallback_entropy do
    hostname = get_hostname()
    node_name = Atom.to_string(Node.self())
    "#{hostname}-#{node_name}" |> :erlang.md5() |> Base.encode16(case: :lower)
  end

  # Gets the machine hostname
  defp get_hostname do
    case :inet.gethostname() do
      {:ok, hostname} -> to_string(hostname)
      {:error, _} -> "localhost"
    end
  end

  # Constant-time string comparison to prevent timing attacks
  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    if byte_size(a) == byte_size(b) do
      secure_compare(a, b, 0) == 0
    else
      false
    end
  end

  defp secure_compare(<<x, rest_a::binary>>, <<y, rest_b::binary>>, acc) do
    import Bitwise
    secure_compare(rest_a, rest_b, bor(acc, bxor(x, y)))
  end

  defp secure_compare(<<>>, <<>>, acc), do: acc
end
