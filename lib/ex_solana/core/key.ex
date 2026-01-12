defmodule ExSolana.Key do
  @moduledoc """
  Solana public key and keypair management.

  ## Features

  - Public key encoding/decoding (Base58)
  - Keypair generation (ed25519)
  - Signature validation

  ## Types

  - `t/0` - Public key (32 bytes, Base58 encoded)
  - `Keypair.t/0` - Keypair with public and private keys
  - `Signature.t/0` - Transaction signature (64 bytes, Base58 encoded)

  ## Examples

      # Generate a new keypair
      keypair = ExSolana.Key.Keypair.generate()
      pubkey = ExSolana.Key.pubkey(keypair)

      # Decode a public key
      {:ok, key} = ExSolana.Key.decode("7mfY3uUuQoJLoQV3wYnTkn6H3Y3NQYjWXxZHFUkgHqE")

      # Create from byte array
      bytes = <<1, 2, 3, ...>> # 32 bytes
      {:ok, key} = ExSolana.Key.from_bytes(bytes)

  ## Error Handling

  All error cases return structured errors via `ExSolana.Error`:

      case ExSolana.Key.decode("invalid") do
        {:ok, key} -> key
        {:error, %ExSolana.Error.InvalidKeyError{} = error} ->
          handle_error(error)
      end
  """

  alias ExSolana.Error

  @typedoc """
  A Solana public key.

  Represented as a 32-byte binary, typically Base58 encoded.
  """
  @type t :: binary()

  @typedoc """
  A Solana keypair containing both public and private keys.
  """
  @type keypair :: %{
          pubkey: t(),
          secret: binary()
        }

  @typedoc """
  A Solana signature.

  Represented as a 64-byte binary, typically Base58 encoded.
  """
  @type signature :: binary()

  @doc """
  The length of a Solana public key in bytes.
  """
  @spec length() :: pos_integer()
  def length, do: 32

  @doc """
  The length of a Solana signature in bytes.
  """
  @spec signature_length() :: pos_integer()
  def signature_length, do: 64

  # ============================================================================
  # Keypair Module
  # ============================================================================

  defmodule Keypair do
    @moduledoc """
    Solana keypair management.

    A keypair consists of a public key (32 bytes) and a private key (64 bytes
    for ed25519, including the seed).

    ## Examples

        # Generate a new random keypair
        keypair = ExSolana.Key.Keypair.generate()

        # Get the public key
        pubkey = ExSolana.Key.Keypair.pubkey(keypair)

        # Sign a message
        message = "Hello, Solana!"
        {:ok, signature} = ExSolana.Key.Keypair.sign(keypair, message)
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                pubkey: Zoi.string(description: "Public key (32 bytes)"),
                secret: Zoi.string(description: "Private key (64 bytes for ed25519)")
              }
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc """
    Generates a new random keypair using ed25519.

    ## Examples

        keypair = ExSolana.Key.Keypair.generate()

    """
    @spec generate() :: t()
    def generate do
      {privkey, pubkey} = Ed25519.generate_key_pair()
      %__MODULE__{pubkey: pubkey, secret: privkey}
    end

    @doc """
    Extracts the public key from a keypair.

    ## Examples

        pubkey = ExSolana.Key.Keypair.pubkey(keypair)

    """
    @spec pubkey(t()) :: ExSolana.Key.t()
    def pubkey(%__MODULE__{} = keypair), do: keypair.pubkey

    @doc """
    Creates a keypair from a raw private key byte array.

    ## Parameters

    - `secret` - A 64-byte ed25519 private key

    ## Examples

        secret = <<1, 2, 3, ...>> # 64 bytes
        {:ok, keypair} = ExSolana.Key.Keypair.from_secret(secret)

    """
    @spec from_secret(binary()) :: {:ok, t()} | {:error, Error.t()}
    def from_secret(secret) when is_binary(secret) do
      with true <- byte_size(secret) == 64,
           {pubkey, ^secret} <- :ed25519.generate_keypair(secret) do
        {:ok, %__MODULE__{pubkey: pubkey, secret: secret}}
      else
        false ->
          {:error, Error.invalid_key_error("Invalid secret key length", reason: :length)}

        _ ->
          {:error, Error.internal_error("Failed to derive public key from secret")}
      end
    end
  end

  # ============================================================================
  # Public Key Functions
  # ============================================================================

  @doc """
  Decodes a Base58 encoded public key.

  ## Parameters

  - `encoded` - Base58 encoded public key string

  ## Returns

  - `{:ok, key}` - Successfully decoded 32-byte public key
  - `{:error, %InvalidKeyError{}}` - Invalid encoding or length

  ## Examples

      {:ok, key} = ExSolana.Key.decode("7mfY3uUuQoJLoQV3wYnTkn6H3Y3NQYjWXxZHFUkgHqE")

      {:error, %ExSolana.Error.InvalidKeyError{}} = ExSolana.Key.decode("invalid")

  """
  @spec decode(String.t()) :: {:ok, t()} | {:error, Error.InvalidKeyError.t()}
  def decode(encoded) when is_binary(encoded) do
    with {:ok, decoded} <- B58.decode58(encoded),
         true <- byte_size(decoded) == 32 do
      {:ok, decoded}
    else
      _ ->
        {:error, Error.invalid_key_error("Invalid public key", key: encoded)}
    end
  end

  @doc """
  Decodes a Base58 encoded public key, raising on error.

  ## Parameters

  - `encoded` - Base58 encoded public key string

  ## Returns

  - 32-byte binary public key

  ## Raises

  - `ArgumentError` - If the encoded string is invalid

  ## Examples

      key = ExSolana.Key.decode!("7mfY3uUuQoJLoQV3wYnTkn6H3Y3NQYjWXxZHFUkgHqE")

  """
  @spec decode!(String.t()) :: t() | no_return()
  def decode!(encoded) when is_binary(encoded) do
    case decode(encoded) do
      {:ok, key} ->
        key

      {:error, %Error.InvalidKeyError{message: message}} ->
        raise ArgumentError, message: message
    end
  end

  @doc """
  Encodes a public key to Base58.

  ## Parameters

  - `key` - 32-byte binary public key

  ## Returns

  - Base58 encoded string

  ## Examples

      key = <<1, 2, 3, ...>> # 32 bytes
      encoded = ExSolana.Key.encode(key)

  """
  @spec encode(t()) :: String.t()
  def encode(key) when is_binary(key) and byte_size(key) == 32 do
    B58.encode58(key)
  end

  @doc """
  Creates a public key from a 32-byte binary.

  ## Parameters

  - `bytes` - 32-byte binary

  ## Returns

  - `{:ok, key}` - Valid public key
  - `{:error, %InvalidKeyError{}}` - Invalid length

  ## Examples

      {:ok, key} = ExSolana.Key.from_bytes(<<1, 2, 3, ...>>)

  """
  @spec from_bytes(binary()) :: {:ok, t()} | {:error, Error.InvalidKeyError.t()}
  def from_bytes(bytes) when is_binary(bytes) do
    if byte_size(bytes) == 32 do
      {:ok, bytes}
    else
      {:error, Error.invalid_key_error("Invalid key length", reason: :length)}
    end
  end

  @doc """
  Derives a public key from another key, a seed, and a program ID.

  The program ID will also serve as the owner of the public key, giving it
  permission to write data to the account.

  ## Parameters

  - `base` - Base public key (32 bytes)
  - `seed` - Seed string
  - `program_id` - Program ID (32 bytes)

  ## Returns

  - `{:ok, derived_key}` - Successfully derived key
  - `{:error, error}` - Invalid base or program_id

  ## Examples

      {:ok, key} = ExSolana.Key.with_seed(base, "seed", program_id)

  """
  @spec with_seed(t(), String.t(), t()) :: {:ok, t()} | {:error, Error.InvalidKeyError.t()}
  def with_seed(base, seed, program_id) do
    with {:ok, base} <- check(base),
         {:ok, program_id} <- check(program_id) do
      [base, seed, program_id]
      |> hash()
      |> check()
    end
  end

  @doc """
  Validates a public key.

  ## Parameters

  - `key` - Any value

  ## Returns

  - `true` - Valid 32-byte public key
  - `false` - Invalid

  ## Examples

      ExSolana.Key.valid?(<<1, 2, 3, ...>>) # => true
      ExSolana.Key.valid?("invalid") # => false

  """
  @spec valid?(any()) :: boolean()
  def valid?(key) when is_binary(key), do: byte_size(key) == 32
  def valid?(_), do: false

  @doc """
  Checks if a value is a valid public key.

  ## Parameters

  - `key` - Any value

  ## Returns

  - `{:ok, key}` - Valid 32-byte public key
  - `{:error, error}` - Invalid

  ## Examples

      {:ok, key} = ExSolana.Key.check(<<1, 2, 3, ...>>)

  """
  @spec check(any()) :: {:ok, t()} | {:error, Error.InvalidKeyError.t()}
  def check(<<key::binary-32>>), do: {:ok, key}
  def check(_), do: {:error, Error.invalid_key_error("invalid public key")}

  @doc """
  Derives a program address from seeds and a program ID.

  ## Parameters

  - `seeds` - List of binary seeds (each <= 32 bytes or byte 0-255)
  - `program_id` - 32-byte program ID

  ## Returns

  - `{:ok, address}` - Successfully derived program-derived address
  - `{:error, :invalid_seeds}` - Seeds are invalid or address is on curve

  ## Examples

      {:ok, pda} = ExSolana.Key.derive_address(["seed"], program_id)

  """
  @spec derive_address([binary()], t()) :: {:ok, t()} | {:error, :invalid_seeds}
  def derive_address(seeds, program_id) do
    with {:ok, program_id} <- check(program_id),
         true <- Enum.all?(seeds, &is_valid_seed?/1) do
      [seeds, program_id, "ProgramDerivedAddress"]
      |> hash()
      |> verify_off_curve()
    else
      {:error, _} = err -> err
      false -> {:error, :invalid_seeds}
    end
  end

  @doc """
  Finds a valid program address.

  Valid addresses must fall off the ed25519 curve; generate a series of nonces,
  then combine each one with the given seeds and program ID until a valid
  address is found.

  ## Parameters

  - `seeds` - List of binary seeds
  - `program_id` - 32-byte program ID

  ## Returns

  - `{:ok, address, nonce}` - Valid address and nonce used
  - `{:error, :no_nonce}` - Could not find valid address

  ## Examples

      {:ok, pda, nonce} = ExSolana.Key.find_address(["seed"], program_id)

  """
  @spec find_address([binary()], t()) :: {:ok, t(), byte()} | {:error, :no_nonce}
  def find_address(seeds, program_id) do
    case check(program_id) do
      {:ok, program_id} ->
        Enum.reduce_while(255..1//-1, {:error, :no_nonce}, fn nonce, acc ->
          case derive_address(List.flatten([seeds, nonce]), program_id) do
            {:ok, address} -> {:halt, {:ok, address, nonce}}
            _err -> {:cont, acc}
          end
        end)

      error ->
        error
    end
  end

  @doc """
  Loads a keypair from a file system wallet.

  Reads a Solana [file system
  wallet](https://docs.solana.com/wallet-guide/file-system-wallet) in the format
  `{private_key, public_key}`. Returns `{:ok, pair}` if successful, or `{:error,
  reason}` if not.

  ## Parameters

  - `path` - Path to the wallet file

  ## Returns

  - `{:ok, {secret_key, public_key}}` - Successfully loaded keypair
  - `{:error, reason}` - File read or format error

  ## Examples

      {:ok, {sk, pk}} = ExSolana.Key.pair_from_file("wallet.json")

  """
  @spec pair_from_file(String.t()) :: {:ok, {t(), t()}} | {:error, term()}
  def pair_from_file(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, list} when is_list(list) <- Jason.decode(contents),
         <<sk::binary-size(32), pk::binary-size(32)>> <- :erlang.list_to_binary(list) do
      {:ok, {sk, pk}}
    else
      {:error, _} = error -> error
      _contents -> {:error, "invalid wallet format"}
    end
  end

  # Private helpers

  defp is_valid_seed?(seed) do
    (is_binary(seed) && byte_size(seed) <= 32) || seed in 0..255
  end

  defp hash(data), do: :crypto.hash(:sha256, data)

  defp verify_off_curve(hash) do
    if Ed25519.on_curve?(hash), do: {:error, :invalid_seeds}, else: {:ok, hash}
  end
end
