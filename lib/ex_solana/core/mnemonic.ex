defmodule ExSolana.Mnemonic do
  @moduledoc """
  Manages mnemonics for generating and deriving keypairs in the Solana ecosystem.

  ## Features

  - Generate BIP39 mnemonic phrases with configurable entropy
  - Derive Solana keypairs from mnemonics using BIP44 paths
  - Support for multiple derived keys with indexing

  ## Solana Derivation Path

  The default Solana derivation path follows BIP44:
  `m/44'/501'/0'/0/0`

  - `44'` - BIP44 purpose
  - `501'` - Solana coin type
  - `0'` - Account index (hardened)
  - `0` - Change index
  - `0` - Address index

  ## Examples

      # Generate a new 24-word mnemonic
      {:ok, mnemonic, keypair} = ExSolana.Mnemonic.generate()

      # Generate a 12-word mnemonic
      {:ok, mnemonic, keypair} = ExSolana.Mnemonic.generate(128)

      # Create from existing phrase
      phrase = "wood cousin rebuild fork animal potato story inherit basic cruel chapter pen"
      {:ok, mnemonic} = ExSolana.Mnemonic.from_phrase(phrase)

      # Derive a key at custom path
      {:ok, mnemonic, keypair} = ExSolana.Mnemonic.derive_key(mnemonic, account: 1)

      # List all derived keys
      ExSolana.Mnemonic.list_derived_keys(mnemonic)

  ## Error Handling

  All error cases return structured errors via `ExSolana.Error`:

      case ExSolana.Mnemonic.generate(64) do
        {:ok, mnemonic, keypair} -> {mnemonic, keypair}
        {:error, %ExSolana.Error.ValidationError{} = error} ->
          handle_error(error)
      end
  """

  alias BlockKeys.CKD
  alias BlockKeys.Encoding
  alias BlockKeys.Mnemonic, as: BKMnemonic
  alias ExSolana.Error

  require Logger

  @solana_purpose "44'"
  @solana_coin_type "501'"
  @default_account "0'"
  @default_change "0"
  @default_address_index "0"

  @default_path "m/#{@solana_purpose}/#{@solana_coin_type}/#{@default_account}/#{@default_change}/#{@default_address_index}"

  @valid_strengths [128, 160, 192, 224, 256]

  @typedoc """
  A mnemonic struct containing the phrase, seed, and derived keys.

  ## Fields

  - `:mnemonic` - The BIP39 mnemonic phrase (space-separated words)
  - `:seed` - The derived seed bytes (hex string)
  - `:derived_keys` - Map of index to {derivation_path, keypair} tuples
  """
  @type t :: %__MODULE__{
          mnemonic: String.t(),
          seed: String.t(),
          derived_keys: %{non_neg_integer() => {String.t(), ExSolana.Key.Keypair.t()}}
        }

  defstruct [:mnemonic, :seed, derived_keys: %{}]

  @doc """
  Returns the default Solana derivation path.

  ## Examples

      ExSolana.Mnemonic.default_derivation_path()
      #=> "m/44'/501'/0'/0/0"

  """
  @spec default_derivation_path() :: String.t()
  def default_derivation_path do
    @default_path
  end

  @doc """
  Generates a new mnemonic phrase with the specified strength.

  ## Parameters

  - `strength` - Entropy strength in bits (128, 160, 192, 224, or 256)
    - 128 bits = 12 words
    - 256 bits = 24 words (default)

  ## Returns

  - `{:ok, mnemonic, keypair}` - Successfully generated mnemonic and derived default keypair
  - `{:error, %ValidationError{}}` - Invalid strength

  ## Examples

      # Generate 24-word mnemonic (default)
      {:ok, mnemonic, {privkey, pubkey}} = ExSolana.Mnemonic.generate()
      byte_size(pubkey) #=> 32

      # Generate 12-word mnemonic
      {:ok, mnemonic, _} = ExSolana.Mnemonic.generate(128)
      String.split(mnemonic.mnemonic) |> length() #=> 12

      # Invalid strength
      {:error, %ExSolana.Error.ValidationError{}} = ExSolana.Mnemonic.generate(64)

  """
  @spec generate(non_neg_integer()) ::
          {:ok, t(), ExSolana.Key.Keypair.t()} | {:error, Error.ValidationError.t()}
  def generate(strength \\ 256)

  def generate(strength) when strength in @valid_strengths do
    entropy = generate_entropy(strength)
    mnemonic_phrase = BKMnemonic.generate_phrase(entropy)
    seed = BKMnemonic.generate_seed(mnemonic_phrase)
    mnemonic = %__MODULE__{mnemonic: mnemonic_phrase, seed: seed}
    derive_key(mnemonic)
  end

  def generate(_strength) do
    {:error,
     Error.validation_error(
       "Invalid mnemonic strength. Must be one of #{inspect(@valid_strengths)}",
       field: :strength
     )}
  end

  @spec generate_entropy(non_neg_integer()) :: binary()
  defp generate_entropy(strength), do: :crypto.strong_rand_bytes(div(strength, 8))

  @doc """
  Validates a mnemonic phrase.

  ## Parameters

  - `mnemonic` - A space-separated BIP39 mnemonic phrase

  ## Returns

  - `{:ok, phrase}` - Valid mnemonic phrase
  - `{:error, %ValidationError{}}` - Invalid mnemonic

  ## Examples

      {:ok, phrase} = ExSolana.Mnemonic.validate("word1 word2 ... word24")

      {:error, %ExSolana.Error.ValidationError{}} = ExSolana.Mnemonic.validate("invalid")

  """
  @spec validate(String.t()) :: {:ok, String.t()} | {:error, Error.ValidationError.t()}
  def validate(mnemonic) when is_binary(mnemonic) do
    if Mnemonic.validate_mnemonic(mnemonic) do
      {:ok, mnemonic}
    else
      {:error, Error.validation_error("Invalid mnemonic phrase", field: :mnemonic)}
    end
  end

  @doc """
  Creates a new Mnemonic struct from a provided mnemonic phrase.

  ## Parameters

  - `phrase` - A valid BIP39 mnemonic phrase (space-separated words)

  ## Returns

  - `{:ok, mnemonic}` - Successfully created mnemonic struct
  - `{:error, %ValidationError{}}` - Invalid mnemonic phrase

  ## Examples

      phrase = "wood cousin rebuild fork animal potato story inherit basic cruel chapter pen"
      {:ok, mnemonic} = ExSolana.Mnemonic.from_phrase(phrase)
      mnemonic.mnemonic == phrase #=> true

  """
  @spec from_phrase(String.t()) :: {:ok, t()} | {:error, Error.ValidationError.t()}
  def from_phrase(phrase) when is_binary(phrase) do
    if Mnemonic.validate_mnemonic(phrase) do
      seed = BKMnemonic.generate_seed(phrase)
      {:ok, %__MODULE__{mnemonic: phrase, seed: seed}}
    else
      {:error, Error.validation_error("Invalid mnemonic phrase", field: :phrase)}
    end
  end

  @doc """
  Derives a keypair from the mnemonic using the specified derivation path options.

  ## Parameters

  - `mnemonic` - The mnemonic struct
  - `opts` - Derivation options
    - `:account` - Account index (default: "0'")
    - `:change` - Change index (default: "0")
    - `:address_index` - Address index (default: "0")

  ## Returns

  - `{:ok, updated_mnemonic, keypair}` - Successfully derived keypair
  - `{:error, %ValidationError{}}` - Invalid derivation path
  - `{:error, %InternalError{}}` - Key derivation failed

  ## Examples

      {:ok, mnemonic, _} = ExSolana.Mnemonic.generate()

      # Derive default key (m/44'/501'/0'/0/0)
      {:ok, mnemonic, {privkey, pubkey}} = ExSolana.Mnemonic.derive_key(mnemonic)
      byte_size(privkey) #=> 32
      byte_size(pubkey) #=> 32

      # Derive key at custom path (m/44'/501'/1'/0/0)
      {:ok, mnemonic, {privkey, pubkey}} = ExSolana.Mnemonic.derive_key(mnemonic, account: 1)

  """
  @spec derive_key(t(), keyword()) ::
          {:ok, t(), ExSolana.Key.Keypair.t()} | {:error, Error.t()}
  def derive_key(%__MODULE__{} = mnemonic, opts \\ []) do
    derivation_path = build_derivation_path(opts)

    with {:ok, validated_path} <- validate_path(derivation_path),
         master_private_key = mnemonic.seed |> CKD.master_keys() |> CKD.master_private_key(),
         child_private_key = CKD.derive(master_private_key, validated_path),
         %{key: private_key} <- Encoding.decode_extended_key(child_private_key) do
      private_key_bytes = binary_part(private_key, byte_size(private_key), -32)
      public_key_bytes = Ed25519.derive_public_key(private_key_bytes)
      keypair = %ExSolana.Key.Keypair{pubkey: public_key_bytes, secret: private_key_bytes}
      index = get_index_from_path(validated_path)

      updated_mnemonic = %{
        mnemonic
        | derived_keys: Map.put(mnemonic.derived_keys, index, {validated_path, keypair})
      }

      {:ok, updated_mnemonic, keypair}
    else
      error ->
        Logger.warning("Failed to derive key: #{inspect(error)}")
        {:error, Error.internal_error("Failed to derive key", details: %{error: inspect(error)})}
    end
  end

  @doc """
  Lists all derived keys from the mnemonic.

  ## Parameters

  - `mnemonic` - The mnemonic struct

  ## Returns

  A list of tuples `{index, {derivation_path, keypair}}` sorted by index.

  ## Examples

      {:ok, mnemonic, _} = ExSolana.Mnemonic.generate()
      {:ok, mnemonic, _} = ExSolana.Mnemonic.derive_key(mnemonic)
      ExSolana.Mnemonic.list_derived_keys(mnemonic)
      #=> [{0, {"m/44'/501'/0'/0/0", %ExSolana.Key.Keypair{...}}]

  """
  @spec list_derived_keys(t()) :: [{non_neg_integer(), {String.t(), ExSolana.Key.Keypair.t()}}]
  def list_derived_keys(%__MODULE__{derived_keys: derived_keys}) do
    Enum.sort(derived_keys)
  end

  @doc """
  Gets a derived key by index.

  ## Parameters

  - `mnemonic` - The mnemonic struct
  - `index` - The derivation index

  ## Returns

  - `{:ok, {derivation_path, keypair}}` - Found the derived key
  - `{:error, %ValidationError{}}` - No key found at index

  ## Examples

      {:ok, mnemonic, _} = ExSolana.Mnemonic.generate()
      {:ok, mnemonic, _} = ExSolana.Mnemonic.derive_key(mnemonic)

      {:ok, {path, keypair}} = ExSolana.Mnemonic.get_derived_key(mnemonic, 0)
      path #=> "m/44'/501'/0'/0/0"

      {:error, %ExSolana.Error.ValidationError{}} = ExSolana.Mnemonic.get_derived_key(mnemonic, 99)

  """
  @spec get_derived_key(t(), non_neg_integer()) ::
          {:ok, {String.t(), ExSolana.Key.Keypair.t()}} | {:error, Error.ValidationError.t()}
  def get_derived_key(%__MODULE__{derived_keys: derived_keys}, index) do
    case Map.fetch(derived_keys, index) do
      {:ok, key} ->
        {:ok, key}

      :error ->
        {:error,
         Error.validation_error("No derived key found for index #{index}",
           field: :index,
           value: index
         )}
    end
  end

  @spec build_derivation_path(keyword()) :: String.t()
  defp build_derivation_path(opts) do
    account = ensure_hardened(Keyword.get(opts, :account, @default_account))
    change = Keyword.get(opts, :change, @default_change)
    address_index = Keyword.get(opts, :address_index, @default_address_index)

    "m/#{@solana_purpose}/#{@solana_coin_type}/#{account}/#{change}/#{address_index}"
  end

  @spec ensure_hardened(String.t() | non_neg_integer()) :: String.t()
  defp ensure_hardened(value) when is_integer(value), do: "#{value}'"

  defp ensure_hardened(value) do
    if String.ends_with?(value, "'"), do: value, else: value <> "'"
  end

  @spec validate_path(String.t()) :: {:ok, String.t()} | {:error, Error.ValidationError.t()}
  defp validate_path(path) do
    if String.match?(
         path,
         ~r/^m\/#{@solana_purpose}\/#{@solana_coin_type}\/\d+'\/\d+\/?(\d+)?$/
       ) do
      {:ok, path}
    else
      {:error,
       Error.validation_error("Invalid Solana derivation path: #{path}",
         field: :derivation_path,
         value: path
       )}
    end
  end

  @spec get_index_from_path(String.t()) :: non_neg_integer()
  defp get_index_from_path(path) do
    path
    |> String.split("/")
    |> List.last()
    |> String.to_integer()
  end
end
