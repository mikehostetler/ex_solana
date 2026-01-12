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

    use Zoi

    @schema Zoi.struct(
              __MODULE__,
              %{
                pubkey:
                  Zoi.binary()
                  |> Zoi.description("Public key (32 bytes)"),
                secret:
                  Zoi.binary()
                  |> Zoi.description("Private key (64 bytes for ed25519)")
              },
              coerce: true
            )

    defstruct [:pubkey, :secret]

    @type t :: %__MODULE__{
            pubkey: ExSolana.Key.t(),
            secret: binary()
          }

    @doc """
    Generates a new random keypair using ed25519.

    ## Examples

        keypair = ExSolana.Key.Keypair.generate()

    """
    @spec generate() :: t()
    def generate do
      {pubkey, privkey} = :ed25519.generate_keypair()
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
    with {:ok, decoded} <- BaseFiftyEight.decode58(encoded),
         true <- byte_size(decoded) == 32 do
      {:ok, decoded}
    else
      _ ->
        {:error, Error.invalid_key_error("Invalid public key", key: encoded)}
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
    BaseFiftyEight.encode58(key)
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
end
