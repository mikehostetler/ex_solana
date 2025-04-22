defmodule ExSolana.Key do
  @moduledoc """
  Functions for creating and validating Solana
  [keys](https://docs.solana.com/terminology#public-key-pubkey) and
  [keypairs](https://docs.solana.com/terminology#keypair).
  """
  require Logger

  @typedoc "Solana public or private key"
  @type t :: Ed25519.key()

  @typedoc "a public/private keypair"
  @type pair :: {t(), t()}

  @spec pair() :: pair

  # @solana_derivation_path "m/44'/501'/0'/0'"
  @doc """
  Generates a public/private key pair in the format `{private_key, public_key}`
  """
  defdelegate pair, to: Ed25519, as: :generate_key_pair

  @doc """
  Reads a public/private key pair from a [file system
  wallet](https://docs.solana.com/wallet-guide/file-system-wallet) in the format
  `{private_key, public_key}`. Returns `{:ok, pair}` if successful, or `{:error,
  reason}` if not.
  """
  @spec pair_from_file(String.t()) :: {:ok, pair} | {:error, term}
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

  @doc """
  Decodes a base58-encoded key and returns it in a tuple.

  If it fails, return an error tuple.
  """
  @spec decode(encoded :: binary) :: {:ok, t} | {:error, binary}
  def decode(encoded) when is_binary(encoded) do
    case B58.decode58(encoded) do
      {:ok, decoded} -> check(decoded)
      _ -> {:error, "invalid public key"}
    end
  end

  def decode(_), do: {:error, "invalid public key"}

  @doc """
  Decodes a base58-encoded key and returns it.

  Throws an `ArgumentError` if it fails.
  """
  @spec decode!(encoded :: binary) :: t
  def decode!(encoded) when is_binary(encoded) do
    case decode(encoded) do
      {:ok, key} ->
        key

      {:error, _} ->
        raise ArgumentError, "invalid public key input: #{encoded}"
    end
  end

  @doc """
  Encodes a key to its base58 representation.

  Returns `{:ok, encoded_key}` if successful, or an error tuple if the input is not a valid key.
  """
  @spec encode(key :: t) :: {:ok, binary} | {:error, binary}
  def encode(key) do
    case check(key) do
      {:ok, valid_key} -> {:ok, B58.encode58(valid_key)}
      error -> error
    end
  end

  @doc """
  Encodes a key to its base58 representation.

  Raises an `ArgumentError` if the input is not a valid key.
  """
  @spec encode!(key :: t) :: binary
  def encode!(key) do
    case encode(key) do
      {:ok, encoded} -> encoded
      {:error, _} -> raise ArgumentError, "invalid key input: #{inspect(key)}"
    end
  end

  @doc """
  Checks to see if a `t:Solana.Key.t/0` is valid.
  """
  @spec check(key :: binary) :: {:ok, t} | {:error, binary}
  def check(key)
  def check(<<key::binary-32>>), do: {:ok, key}
  def check(_), do: {:error, "invalid public key"}

  @doc """
  Derive a public key from another key, a seed, and a program ID.

  The program ID will also serve as the owner of the public key, giving it
  permission to write data to the account.
  """
  @spec with_seed(base :: t, seed :: binary, program_id :: t) ::
          {:ok, t} | {:error, binary}
  def with_seed(base, seed, program_id) do
    with {:ok, base} <- check(base),
         {:ok, program_id} <- check(program_id) do
      [base, seed, program_id]
      |> hash()
      |> check()
    end
  end

  @doc """
  Derives a program address from seeds and a program ID.
  """
  @spec derive_address(seeds :: [binary], program_id :: t) ::
          {:ok, t} | {:error, term}
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

  defp is_valid_seed?(seed) do
    (is_binary(seed) && byte_size(seed) <= 32) || seed in 0..255
  end

  defp hash(data), do: :crypto.hash(:sha256, data)

  defp verify_off_curve(hash) do
    if Ed25519.on_curve?(hash), do: {:error, :invalid_seeds}, else: {:ok, hash}
  end

  @doc """
  Finds a valid program address.

  Valid addresses must fall off the ed25519 curve; generate a series of nonces,
  then combine each one with the given seeds and program ID until a valid
  address is found. If a valid address is found, return the address and the
  nonce in a tuple. Otherwise, return an error tuple.
  """
  @spec find_address(seeds :: [binary], program_id :: t) ::
          {:ok, t, nonce :: byte} | {:error, :no_nonce}
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
  Creates a keypair from a base58-encoded public key and private key.
  """
  @spec from_secret_key(binary()) :: {:ok, t()} | {:error, atom()}
  def from_base58(secret_key, opts \\ []) do
    with {:ok, secret_key} <- B58.decode58(secret_key),
         {:ok, keypair} <- from_secret_key(secret_key, opts) do
      {:ok, keypair}
    else
      error ->
        Logger.warning("Failed to decode keypair: #{inspect(error)}")
        {:error, :invalid_keypair}
    end
  end

  @doc """
  Creates a keypair from a secret key.
  """
  @spec from_secret_key(binary(), keyword()) :: {:ok, t()} | {:error, atom()}
  def from_secret_key(secret_key, opts \\ []) do
    skip_validation = Keyword.get(opts, :skip_validation, false)

    with :ok <- validate_secret_key_size(secret_key),
         {private_key, public_key} <- split_secret_key(secret_key),
         :ok <- maybe_validate_public_key(private_key, public_key, skip_validation) do
      {:ok, {private_key, public_key}}
    end
  end

  defp validate_secret_key_size(secret_key) do
    if byte_size(secret_key) == 64, do: :ok, else: {:error, :bad_secret_key_size}
  end

  defp split_secret_key(<<private_key::binary-size(32), public_key::binary-size(32)>>), do: {private_key, public_key}

  defp maybe_validate_public_key(_private_key, _public_key, true), do: :ok

  defp maybe_validate_public_key(private_key, public_key, false) do
    computed_public_key = Ed25519.derive_public_key(private_key)
    if computed_public_key == public_key, do: :ok, else: {:error, :invalid_secret_key}
  end
end
