defmodule ExSolana.Native.SystemProgram do
  @moduledoc """
  Functions for interacting with Solana's [System
  Program](https://docs.solana.com/developing/runtime-facilities/programs#system-program)
  """

  use ExSolana.ProgramBehaviour,
    program_id: "11111111111111111111111111111111"

  import ExSolana.Helpers

  alias ExSolana.Account
  alias ExSolana.Instruction

  require IEx
  require Logger

  @doc """
  The System Program's program ID.
  """
  @impl true
  def id, do: ExSolana.pubkey!("11111111111111111111111111111111")

  @create_account_schema [
    lamports: [
      type: :pos_integer,
      required: true,
      doc: "Amount of lamports to transfer to the created account"
    ],
    space: [
      type: :non_neg_integer,
      required: true,
      doc: "Amount of space in bytes to allocate to the created account"
    ],
    from: [
      type: {:custom, ExSolana.Key, :check, []},
      required: true,
      doc: "The account that will transfer lamports to the created account"
    ],
    new: [
      type: {:custom, ExSolana.Key, :check, []},
      required: true,
      doc: "Public key of the created account"
    ],
    program_id: [
      type: {:custom, ExSolana.Key, :check, []},
      required: true,
      doc: "Public key of the program which will own the created account"
    ],
    base: [
      type: {:custom, ExSolana.Key, :check, []},
      doc: "Base public key to use to derive the created account's address"
    ],
    seed: [
      type: :string,
      doc: "Seed to use to derive the created account's address"
    ]
  ]
  @doc """
  Generates instructions to create a new account.

  Accepts a `new` address generated via `ExSolana.Key.with_seed/3`, as long as the
  `base` key and `seed` used to generate that address are provided.

  ## Options

  #{NimbleOptions.docs(@create_account_schema)}
  """
  def create_account(opts) do
    case validate(opts, @create_account_schema) do
      {:ok, params} ->
        maybe_with_seed(
          params,
          &create_account_ix/1,
          &create_account_with_seed_ix/1,
          [:base, :seed]
        )

      error ->
        error
    end
  end

  @transfer_schema [
    lamports: [
      type: :pos_integer,
      required: true,
      doc: "Amount of lamports to transfer"
    ],
    from: [
      type: {:custom, ExSolana.Key, :check, []},
      required: true,
      doc: "Account that will transfer lamports"
    ],
    to: [
      type: {:custom, ExSolana.Key, :check, []},
      required: true,
      doc: "Account that will receive the transferred lamports"
    ],
    base: [
      type: {:custom, ExSolana.Key, :check, []},
      doc: "Base public key to use to derive the funding account address"
    ],
    seed: [
      type: :string,
      doc: "Seed to use to derive the funding account address"
    ],
    program_id: [
      type: {:custom, ExSolana.Key, :check, []},
      doc: "Program ID to use to derive the funding account address"
    ]
  ]
  @doc """
  Generates instructions to transfer lamports from one account to another.

  Accepts a `from` address generated via `ExSolana.Key.with_seed/3`, as long as the
  `base` key, `program_id`, and `seed` used to generate that address are
  provided.

  ## Options

  #{NimbleOptions.docs(@transfer_schema)}
  """
  def transfer(opts) do
    case validate(opts, @transfer_schema) do
      {:ok, params} ->
        maybe_with_seed(
          params,
          &transfer_ix/1,
          &transfer_with_seed_ix/1
        )

      error ->
        error
    end
  end

  @batch_transfer_schema [
    transfers: [
      type:
        {:list,
         {:tuple,
          [
            {:custom, ExSolana.Key, :check, []},
            {:custom, ExSolana.Key, :check, []},
            :pos_integer
          ]}},
      required: true,
      doc: "List of transfers, each as a tuple of {from, to, amount}"
    ],
    max_instructions_per_transaction: [
      type: :pos_integer,
      default: 5,
      doc: "Maximum number of transfer instructions per transaction"
    ]
  ]
  @doc """
  Generates instructions to transfer lamports from one account to multiple accounts.

  ## Options

  #{NimbleOptions.docs(@batch_transfer_schema)}
  """
  def batch_transfer(opts) do
    case validate(opts, @batch_transfer_schema) do
      {:ok, params} ->
        instructions =
          Enum.map(params.transfers, fn {from, to, amount} ->
            transfer(from: from, to: to, lamports: amount)
          end)

        chunked_instructions =
          Enum.chunk_every(instructions, params.max_instructions_per_transaction)

        {:ok, chunked_instructions}

      error ->
        error
    end
  end

  @assign_schema [
    account: [
      type: {:custom, ExSolana.Key, :check, []},
      required: true,
      doc: "Public key for the account which will receive a new owner"
    ],
    program_id: [
      type: {:custom, ExSolana.Key, :check, []},
      required: true,
      doc: "Program ID to assign as the owner"
    ],
    base: [
      type: {:custom, ExSolana.Key, :check, []},
      doc: "Base public key to use to derive the assigned account address"
    ],
    seed: [
      type: :string,
      doc: "Seed to use to derive the assigned account address"
    ]
  ]
  @doc """
  Generates instructions to assign account ownership to a program.

  Accepts an `account` address generated via `ExSolana.Key.with_seed/3`, as long
  as the `base` key and `seed` used to generate that address are provided.

  ## Options

  #{NimbleOptions.docs(@assign_schema)}
  """
  def assign(opts) do
    case validate(opts, @assign_schema) do
      {:ok, params} ->
        maybe_with_seed(
          params,
          &assign_ix/1,
          &assign_with_seed_ix/1,
          [:base, :seed]
        )

      error ->
        error
    end
  end

  @allocate_schema [
    account: [
      type: {:custom, ExSolana.Key, :check, []},
      required: true,
      doc: "Public key for the account to allocate"
    ],
    space: [
      type: :non_neg_integer,
      required: true,
      doc: "Amount of space in bytes to allocate"
    ],
    program_id: [
      type: {:custom, ExSolana.Key, :check, []},
      doc: "Program ID to assign as the owner of the allocated account"
    ],
    base: [
      type: {:custom, ExSolana.Key, :check, []},
      doc: "Base public key to use to derive the allocated account address"
    ],
    seed: [
      type: :string,
      doc: "Seed to use to derive the allocated account address"
    ]
  ]
  @doc """
  Generates instructions to allocate space to an account.

  Accepts an `account` address generated via `ExSolana.Key.with_seed/3`, as long
  as the `base` key, `program_id`, and `seed` used to generate that address are
  provided.

  ## Options

  #{NimbleOptions.docs(@allocate_schema)}
  """
  def allocate(opts) do
    case validate(opts, @allocate_schema) do
      {:ok, params} ->
        maybe_with_seed(
          params,
          &allocate_ix/1,
          &allocate_with_seed_ix/1,
          [:base, :seed]
        )

      error ->
        error
    end
  end

  @doc """
  Decodes a System Program instruction from the given binary data.
  Returns a tuple with the instruction type and its parameters.
  """
  @impl ExSolana.ProgramBehaviour
  def decode_ix(data) do
    case data do
      <<0::little-32, lamports::little-64, space::little-64, owner::binary-32>> ->
        {:create_account, %{lamports: lamports, space: space, owner: B58.encode58(owner)}}

      <<1::little-32, owner::binary-32>> ->
        {:assign, %{owner: B58.encode58(owner)}}

      <<2::little-32, lamports::little-64>> ->
        {:transfer, %{lamports: lamports}}

      # <<3::little-32, rest::binary>> ->
      #   require IEx

      #   IEx.pry()

      #   <<base::binary-32, rest::binary>> = rest
      #   IO.puts("Base (raw): #{inspect(base)}")
      #   IO.puts("Base (Base58): #{B58.encode58(base)}")
      #   IEx.pry()
      #   <<seed_len::little-32, rest::binary>> = rest
      #   <<seed::binary-size(seed_len), rest::binary>> = rest
      #   IO.puts("Seed length: #{seed_len}")
      #   IO.puts("Seed: #{seed}")
      #   IEx.pry()
      #   <<lamports::little-64, space::little-64, owner::binary-32>> = rest
      #   IO.puts("Lamports: #{lamports}")
      #   IO.puts("Space: #{space}")
      #   IO.puts("Owner (Base58): #{B58.encode58(owner)}")
      #   IEx.pry()

      # <<3::little-32, base::binary-32, seed_len::little-32, seed::binary-size(seed_len), lamports::little-64,
      #   space::little-64, owner::binary-32>> ->
      <<3::little-32, base::binary-32, seed_len::little-32, _buffer::binary-size(4),
        seed::binary-size(seed_len), lamports::little-64, space::little-64, owner::binary-32,
        _rest::binary>> ->
        {:create_account_with_seed,
         %{
           base: B58.encode58(base),
           seed: seed,
           lamports: Integer.to_string(lamports),
           space: Integer.to_string(space),
           owner: B58.encode58(owner)
         }}

      <<4::little-32>> ->
        {:advance_nonce_account, %{}}

      <<5::little-32, lamports::little-64>> ->
        {:withdraw_nonce_account, %{lamports: lamports}}

      <<6::little-32, authority::binary-32>> ->
        {:initialize_nonce_account, %{authority: B58.encode58(authority)}}

      <<7::little-32, authority::binary-32>> ->
        {:authorize_nonce_account, %{authority: B58.encode58(authority)}}

      <<8::little-32, space::little-64>> ->
        {:allocate, %{space: space}}

      <<9::little-32, base::binary-32, seed_len::little-32, seed::binary-size(seed_len),
        space::little-64, owner::binary-32>> ->
        {:allocate_with_seed,
         %{base: B58.encode58(base), seed: seed, space: space, owner: B58.encode58(owner)}}

      <<10::little-32, base::binary-32, seed_len::little-32, seed::binary-size(seed_len),
        owner::binary-32>> ->
        {:assign_with_seed, %{base: B58.encode58(base), seed: seed, owner: B58.encode58(owner)}}

      <<11::little-32, lamports::little-64, from_seed_len::little-32,
        from_seed::binary-size(from_seed_len), from_owner::binary-32>> ->
        {:transfer_with_seed,
         %{lamports: lamports, from_seed: from_seed, from_owner: B58.encode58(from_owner)}}

      <<12::little-32>> ->
        {:upgrade_nonce_account, %{}}

      <<2_778_650_768_847_142_915::little-64, rest::binary>> ->
        decode_ix(<<3::little-32, rest::binary>>)

      _ ->
        Logger.warning("Unknown System Program instruction", data: Base.encode64(data))
        {:unknown, %{data: Base.encode64(data)}}
    end
  end

  @impl ExSolana.ProgramBehaviour
  def analyze_ix(decoded_parsed_ix, _confirmed_transaction) do
    case decoded_parsed_ix.decoded_ix do
      {:transfer, params} ->
        [%{key: from}, %{key: to}] = decoded_parsed_ix.ix.accounts

        %ExSolana.Actions.SolTransfer{
          amount: params.lamports,
          sender: from,
          recipient: to
        }

      # {:create_account, params} ->
      #   %ExSolana.Actions.CreateAccount{
      #     lamports: params.lamports,
      #     space: params.space,
      #     owner: params.owner
      #   }

      # {instruction_type, params} when is_atom(instruction_type) ->
      #   {}
      #   Map.put(params, :type, instruction_type)

      _ ->
        {:unknown_action, %{}}
    end
  end

  defp maybe_with_seed(opts, ix_fn, ix_seed_fn, keys \\ [:base, :seed, :program_id]) do
    key_check = Enum.map(keys, &Map.has_key?(opts, &1))

    cond do
      Enum.all?(key_check) -> ix_seed_fn.(opts)
      !Enum.any?(key_check) -> ix_fn.(opts)
      true -> {:error, :missing_seed_params}
    end
  end

  defp create_account_ix(params) do
    %Instruction{
      program: id(),
      accounts: [
        %Account{key: params.from, signer?: true, writable?: true},
        %Account{key: params.new, signer?: true, writable?: true}
      ],
      data:
        Instruction.encode_data([
          {0, 32},
          {params.lamports, 64},
          {params.space, 64},
          params.program_id
        ])
    }
  end

  defp create_account_with_seed_ix(params) do
    %Instruction{
      program: id(),
      accounts: create_account_with_seed_accounts(params),
      data:
        Instruction.encode_data([
          {3, 32},
          params.base,
          {params.seed, "str"},
          {params.lamports, 64},
          {params.space, 64},
          params.program_id
        ])
    }
  end

  defp create_account_with_seed_accounts(%{from: from, base: from} = params) do
    [
      %Account{key: from, signer?: true, writable?: true},
      %Account{key: params.new, writable?: true}
    ]
  end

  defp create_account_with_seed_accounts(params) do
    [
      %Account{key: params.from, signer?: true, writable?: true},
      %Account{key: params.new, writable?: true},
      %Account{key: params.base, signer?: true}
    ]
  end

  defp transfer_ix(params) do
    %Instruction{
      program: id(),
      accounts: [
        %Account{key: params.from, signer?: true, writable?: true},
        %Account{key: params.to, writable?: true}
      ],
      data: Instruction.encode_data([{2, 32}, {params.lamports, 64}])
    }
  end

  defp transfer_with_seed_ix(params) do
    %Instruction{
      program: id(),
      accounts: [
        %Account{key: params.from, writable?: true},
        %Account{key: params.base, signer?: true},
        %Account{key: params.to, writable?: true}
      ],
      data:
        Instruction.encode_data([
          {11, 32},
          {params.lamports, 64},
          {params.seed, "str"},
          params.program_id
        ])
    }
  end

  defp assign_ix(params) do
    %Instruction{
      program: id(),
      accounts: [
        %Account{key: params.account, signer?: true, writable?: true}
      ],
      data: Instruction.encode_data([{1, 32}, params.program_id])
    }
  end

  defp assign_with_seed_ix(params) do
    %Instruction{
      program: id(),
      accounts: [
        %Account{key: params.account, writable?: true},
        %Account{key: params.base, signer?: true}
      ],
      data:
        Instruction.encode_data([
          {10, 32},
          params.base,
          {params.seed, "str"},
          params.program_id
        ])
    }
  end

  defp allocate_ix(params) do
    %Instruction{
      program: id(),
      accounts: [
        %Account{key: params.account, signer?: true, writable?: true}
      ],
      data: Instruction.encode_data([{8, 32}, {params.space, 64}])
    }
  end

  defp allocate_with_seed_ix(params) do
    %Instruction{
      program: id(),
      accounts: [
        %Account{key: params.account, writable?: true},
        %Account{key: params.base, signer?: true}
      ],
      data:
        Instruction.encode_data([
          {9, 32},
          params.base,
          {params.seed, "str"},
          {params.space, 64},
          params.program_id
        ])
    }
  end
end
