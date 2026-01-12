defmodule ExSolana.Account do
  @moduledoc """
  Solana account structures and utilities.

  ## Features

  - Account struct for transaction encoding
  - Account information from RPC
  - Account validation

  ## Examples

      # Create an account reference
      account = ExSolana.Account.new(%{
        key: pubkey,
        signer?: true,
        writable?: true
      })

      # Decode account info from RPC
      {:ok, account_info} = ExSolana.Account.Info.from_rpc(response)

  ## Error Handling

  All error cases return structured errors via `ExSolana.Error`:

      case ExSolana.Account.decode_account(data) do
        {:ok, account} -> account
        {:error, %ExSolana.Error.ValidationError{} = error} ->
          handle_error(error)
      end
  """

  alias ExSolana.{Error, Key}

  @typedoc """
  Account reference for transaction encoding.

  Used to specify which accounts are involved in a transaction and how.
  """
  @type t :: %__MODULE__{
          key: Key.t() | nil,
          signer?: boolean(),
          writable?: boolean()
        }

  @typedoc """
  All the information needed to encode an account in a transaction message.
  """
  @type account :: %__MODULE__{
          key: Key.t() | nil,
          signer?: boolean(),
          writable?: boolean()
        }

  @schema Zoi.struct(
            __MODULE__,
            %{
              key:
                Zoi.string(description: "Account public key")
                |> Zoi.optional(),
              signer?:
                Zoi.boolean(description: "Whether account signs the transaction")
                |> Zoi.default(false),
              writable?:
                Zoi.boolean(description: "Whether account is writable")
                |> Zoi.default(false)
            },
            coerce: true
          )

  @type t_schema :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Creates a new Account struct from a map of parameters.

  ## Parameters

  - `params`: A map containing the following optional keys:
    - `:key` - The account's public key (ExSolana.key())
    - `:signer?` - Boolean indicating if the account is a signer (default: false)
    - `:writable?` - Boolean indicating if the account is writable (default: false)

  ## Examples

      iex> ExSolana.Account.new(%{key: "some_public_key", signer?: true})
      %ExSolana.Account{key: "some_public_key", signer?: true, writable?: false}

  """
  @spec new(map()) :: t()
  def new(params) when is_map(params) do
    %__MODULE__{
      key: Map.get(params, :key),
      signer?: Map.get(params, :signer?, false),
      writable?: Map.get(params, :writable?, false)
    }
  end

  @doc """
  Creates an account that signs the transaction.
  """
  @spec signer(Key.t()) :: t()
  def signer(key) when is_binary(key) do
    %__MODULE__{key: key, signer?: true, writable?: false}
  end

  @doc """
  Creates a writable account.
  """
  @spec writable(Key.t()) :: t()
  def writable(key) when is_binary(key) do
    %__MODULE__{key: key, signer?: false, writable?: true}
  end

  @doc """
  Creates a writable signer account.
  """
  @spec signer_writable(Key.t()) :: t()
  def signer_writable(key) when is_binary(key) do
    %__MODULE__{key: key, signer?: true, writable?: true}
  end

  @doc """
  Creates a read-only account reference.
  """
  @spec readonly(Key.t()) :: t()
  def readonly(key) when is_binary(key) do
    %__MODULE__{key: key, signer?: false, writable?: false}
  end

  # ============================================================================
  # Account Info Module
  # ============================================================================

  defmodule Info do
    @moduledoc """
    Account information from RPC.

    Represents the data returned by `getAccountInfo` RPC calls.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                lamports: Zoi.integer(description: "Account balance in lamports"),
                data: Zoi.string(description: "Account data"),
                owner: Zoi.string(description: "Owner program public key"),
                executable:
                  Zoi.boolean(description: "Whether account is executable")
                  |> Zoi.default(false),
                rent_epoch:
                  Zoi.integer(description: "Rent epoch")
                  |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc """
    Creates account info from RPC response.

    ## Parameters

    - `rpc_response` - Map from RPC response containing account info

    ## Examples

        {:ok, info} = ExSolana.Account.Info.from_rpc(%{
          "value" => %{
            "lamports" => 1000000,
            "data" => ["base64encoded", "base64"],
            "owner" => "OwnerPubkey",
            "executable" => false
          }
        })

    """
    @spec from_rpc(map()) :: {:ok, t()} | {:error, Error.t()}
    def from_rpc(%{"value" => value}) when is_map(value) do
      with {:ok, lamports} <- fetch_lamports(value),
           {:ok, data} <- fetch_data(value),
           {:ok, owner} <- fetch_owner(value),
           executable <- Map.get(value, "executable", false) do
        {:ok,
         %__MODULE__{
           lamports: lamports,
           data: data,
           owner: owner,
           executable: executable,
           rent_epoch: Map.get(value, "rentEpoch")
         }}
      else
        {:error, _} = error -> error
        _ -> {:error, Error.validation_error("Invalid account info response")}
      end
    end

    def from_rpc(_), do: {:error, Error.validation_error("Invalid RPC response format")}

    defp fetch_lamports(value) do
      case Map.get(value, "lamports") do
        nil -> {:error, Error.validation_error("Missing lamports", field: :lamports)}
        lamports when is_integer(lamports) -> {:ok, lamports}
        _ -> {:error, Error.validation_error("Invalid lamports type", field: :lamports)}
      end
    end

    defp fetch_data(value) do
      case Map.get(value, "data") do
        nil ->
          {:ok, <<>>}

        [encoded, "base64"] when is_binary(encoded) ->
          case Base.decode64(encoded) do
            {:ok, decoded} -> {:ok, decoded}
            :error -> {:error, Error.validation_error("Invalid base64 data", field: :data)}
          end

        _ ->
          {:error, Error.validation_error("Invalid data format", field: :data)}
      end
    end

    defp fetch_owner(value) do
      case Map.get(value, "owner") do
        nil -> {:error, Error.validation_error("Missing owner", field: :owner)}
        owner when is_binary(owner) -> {:ok, owner}
        _ -> {:error, Error.validation_error("Invalid owner type", field: :owner)}
      end
    end
  end
end
