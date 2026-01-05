defmodule ExSolana.Mnemonic do
  @moduledoc """
  Manages mnemonics for generating and deriving keypairs in the Solana ecosystem.
  """

  alias BlockKeys.CKD
  alias BlockKeys.Encoding
  alias BlockKeys.Mnemonic, as: BKMnemonic

  require Logger

  @solana_purpose "44'"
  @solana_coin_type "501'"
  @default_account "0'"
  @default_change "0"
  @default_address_index "0"

  @default_path "m/#{@solana_purpose}/#{@solana_coin_type}/#{@default_account}/#{@default_change}/#{@default_address_index}"

  @valid_strengths [128, 160, 192, 224, 256]

  @type t :: %__MODULE__{
          mnemonic: String.t(),
          seed: String.t(),
          derived_keys: %{non_neg_integer() => {String.t(), ExSolana.Key.pair()}}
        }

  defstruct [:mnemonic, :seed, derived_keys: %{}]

  def default_derivation_path do
    @default_path
  end

  @doc """
  Generates a new mnemonic phrase with the specified strength.

  ## Examples

      iex> {:ok, mnemonic, _} = ExSolana.Mnemonic.generate()
      iex> String.split(mnemonic.mnemonic) |> length()
      24

      iex> {:ok, mnemonic, _} = ExSolana.Mnemonic.generate(128)
      iex> String.split(mnemonic.mnemonic) |> length()
      12
  """
  @spec generate(non_neg_integer()) :: {:ok, t(), ExSolana.Key.pair()} | {:error, String.t()}
  def generate(strength \\ 256)

  def generate(strength) when strength in @valid_strengths do
    entropy = generate_entropy(strength)
    mnemonic_phrase = BKMnemonic.generate_phrase(entropy)
    seed = BKMnemonic.generate_seed(mnemonic_phrase)
    mnemonic = %__MODULE__{mnemonic: mnemonic_phrase, seed: seed}
    # {:ok, _mnemonic, keypair} = derive_key(mnemonic)
    derive_key(mnemonic)
    # {:ok, %{mnemonic | derived_keys: %{@default_derivation_path => keypair}}, keypair}
  end

  def generate(_strength) do
    {:error, "Invalid mnemonic strength. Must be one of #{inspect(@valid_strengths)}"}
  end

  @spec generate_entropy(non_neg_integer()) :: binary()
  defp generate_entropy(strength), do: :crypto.strong_rand_bytes(div(strength, 8))

  def validate(mnemonic) do
    if Mnemonic.validate_mnemonic(mnemonic) do
      {:ok, mnemonic}
    else
      {:error, "Invalid mnemonic phrase"}
    end
  end

  @doc """
  Creates a new Mnemonic struct from a provided mnemonic phrase.

  ## Examples

      iex> phrase = "wood cousin rebuild fork animal potato story inherit basic cruel chapter pen"
      iex> {:ok, mnemonic} = ExSolana.Mnemonic.from_phrase(phrase)
      iex> mnemonic.mnemonic == phrase
      true
  """
  @spec from_phrase(String.t()) :: {:ok, t()} | {:error, String.t()}
  def from_phrase(phrase) when is_binary(phrase) do
    if Mnemonic.validate_mnemonic(phrase) do
      seed = BKMnemonic.generate_seed(phrase)
      {:ok, %__MODULE__{mnemonic: phrase, seed: seed}}
    else
      {:error, "Invalid mnemonic phrase"}
    end
  end

  @doc """
  Derives a key from the mnemonic using the specified derivation path.

  ## Examples

      iex> {:ok, mnemonic, _} = ExSolana.Mnemonic.generate()
      iex> {:ok, mnemonic, keypair} = ExSolana.Mnemonic.derive_key(mnemonic)
      iex> {private_key, public_key} = keypair
      iex> is_binary(private_key) and byte_size(private_key) == 32
      true
      iex> is_binary(public_key) and byte_size(public_key) == 32
      true
  """
  @spec derive_key(t(), keyword()) :: {:ok, t(), ExSolana.Key.pair()} | {:error, String.t()}
  def derive_key(%__MODULE__{} = mnemonic, opts \\ []) do
    derivation_path = build_derivation_path(opts)

    with {:ok, validated_path} <- validate_path(derivation_path),
         master_private_key = mnemonic.seed |> CKD.master_keys() |> CKD.master_private_key(),
         child_private_key = CKD.derive(master_private_key, validated_path),
         %{key: private_key} <- Encoding.decode_extended_key(child_private_key) do
      private_key_bytes = binary_part(private_key, byte_size(private_key), -32)
      public_key_bytes = Ed25519.derive_public_key(private_key_bytes)
      keypair = {private_key_bytes, public_key_bytes}
      index = get_index_from_path(validated_path)

      updated_mnemonic = %{
        mnemonic
        | derived_keys: Map.put(mnemonic.derived_keys, index, {validated_path, keypair})
      }

      {:ok, updated_mnemonic, keypair}
    else
      error ->
        Logger.warning("Failed to derive key: #{inspect(error)}")
        {:error, "Failed to derive key"}
    end
  end

  @doc """
  Lists all derived keys.

  ## Examples

      iex> {:ok, mnemonic, _} = ExSolana.Mnemonic.generate()
      iex> {:ok, mnemonic, _} = ExSolana.Mnemonic.derive_key(mnemonic)
      iex> ExSolana.Mnemonic.list_derived_keys(mnemonic)
      [{0, {"m/44'/501'/0'/0/0", {{private_key_bytes}, {public_key_bytes}}}}]
  """
  @spec list_derived_keys(t()) :: [{non_neg_integer(), {String.t(), ExSolana.Key.pair()}}]
  def list_derived_keys(%__MODULE__{derived_keys: derived_keys}) do
    Enum.sort(derived_keys)
  end

  @doc """
  Gets a derived key by index.

  ## Examples

      iex> {:ok, mnemonic, _} = ExSolana.Mnemonic.generate()
      iex> {:ok, mnemonic, _} = ExSolana.Mnemonic.derive_key(mnemonic)
      iex> ExSolana.Mnemonic.get_derived_key(mnemonic, 0)
      {:ok, {"m/44'/501'/0'/0/0", {{private_key_bytes}, {public_key_bytes}}}}
  """
  @spec get_derived_key(t(), non_neg_integer()) ::
          {:ok, {String.t(), ExSolana.Key.pair()}} | {:error, String.t()}
  def get_derived_key(%__MODULE__{derived_keys: derived_keys}, index) do
    case Map.fetch(derived_keys, index) do
      {:ok, key} -> {:ok, key}
      :error -> {:error, "No derived key found for index #{index}"}
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

  @spec validate_path(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp validate_path(path) do
    if String.match?(path, ~r/^m\/#{@solana_purpose}\/#{@solana_coin_type}\/\d+'\/\d+\/?(\d+)?$/) do
      {:ok, path}
    else
      {:error, "Invalid Solana derivation path"}
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
