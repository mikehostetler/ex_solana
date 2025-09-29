defmodule ExSolana.Wallet do
  @moduledoc """
  Provides high-level wallet operations for Solana accounts.
  """

  alias ExSolana.RPC
  alias ExSolana.RPC.Request
  alias ExSolana.Token

  require IEx

  @type t :: %__MODULE__{
          address: ExSolana.Key.t(),
          sol_balance: Decimal.t(),
          token_balances: %{Token.t() => Decimal.t()},
          stablecoin_balances: %{Token.t() => Decimal.t()},
          transactions: [ExSolana.Transaction.Core.TransactionInfo.t()],
          activity_summary: map()
        }

  defstruct [
    :address,
    :sol_balance,
    :token_balances,
    :stablecoin_balances,
    :transactions,
    :activity_summary
  ]

  @doc """
  Creates a new wallet struct.
  """
  @spec new(ExSolana.Key.t()) :: t()
  def new(address) do
    %__MODULE__{
      address: address,
      sol_balance: Decimal.new(0),
      token_balances: %{},
      stablecoin_balances: %{},
      transactions: [],
      activity_summary: %{}
    }
  end

  @doc """
  Fetches the entire transaction history for a given wallet address.

  ## Parameters

  - `client`: The RPC client to use for requests.
  - `address`: The public key of the wallet as a base58-encoded string.
  - `opts`: Additional options for the request.

  ## Returns

  A map containing the transaction history and activity summary.
  """
  @spec fetch_transaction_history(RPC.client(), String.t(), keyword()) ::
          {:ok, map()} | {:error, any()}
  def fetch_transaction_history(client, address, opts \\ []) do
    with {:ok, signatures} <- fetch_all_signatures(client, address, opts),
         {:ok, transactions} <- fetch_transactions(client, signatures, opts),
         {:ok, decoded_transactions} <- decode_transactions(transactions) do
      {:ok,
       %{
         address: address,
         transactions: decoded_transactions
       }}
    end
  end

  # @doc """
  # Updates the token balances of the wallet, including stablecoins.
  # """

  # @spec update_token_balances(RPC.client(), t()) :: {:ok, t()} | {:error, any()}
  # def update_token_balances(client, wallet) do
  #   case RPC.send(client, Request.get_token_accounts_by_owner(wallet.address, %{})) do
  #     {:ok, accounts} ->
  #       {token_balances, stablecoin_balances} =
  #         Enum.reduce(accounts, {%{}, %{}}, fn account, {tokens, stables} ->
  #           token = Token.get_by_mint(account.mint)
  #           balance = Decimal.new(account.amount)

  #           if Token.stablecoin?(token) do
  #             {tokens, Map.put(stables, token, balance)}
  #           else
  #             {Map.put(tokens, token, balance), stables}
  #           end
  #         end)

  #       {:ok,
  #        %{wallet | token_balances: token_balances, stablecoin_balances: stablecoin_balances}}

  #     error ->
  #       error
  #   end
  # end

  @doc """
  Updates the SOL balance of the wallet.
  """
  @spec update_sol_balance(t()) :: {:ok, t()} | {:error, any()}
  def update_sol_balance(wallet) do
    client = ExSolana.rpc_client()

    case RPC.send(client, Request.get_balance(wallet.address)) do
      {:ok, balance} ->
        {:ok, %{wallet | sol_balance: Decimal.new(balance)}}

      error ->
        error
    end
  end

  def fetch_all_signatures(client, address, opts) do
    fetch_signatures_recursively(client, address, opts, [])
  end

  defp fetch_signatures_recursively(client, address, opts, acc) do
    case RPC.send(client, Request.get_signatures_for_address(address, opts)) do
      {:ok, [signatures]} ->
        new_acc = acc ++ signatures

        case List.last(signatures) do
          nil ->
            {:ok, new_acc}

          last ->
            new_opts = Keyword.put(opts, :before, last["signature"])
            fetch_signatures_recursively(client, address, new_opts, new_acc)
        end

      error ->
        error
    end
  end

  def fetch_transactions(client, signatures, opts) do
    # Merge the maxSupportedTransactionVersion into the opts
    opts =
      Keyword.put(opts, :max_supported_transaction_version, 0)

    # Add a default limit of 100 transactions
    limit = Keyword.get(opts, :limit, 100)

    signatures
    |> Enum.map(& &1["signature"])
    |> Enum.take(limit)
    |> Enum.reduce_while({:ok, []}, fn signature, {:ok, acc} ->
      case RPC.send(client, Request.get_transaction(signature, opts)) do
        {:ok, transaction} ->
          {:cont, {:ok, [transaction | acc]}}

        {:error, %{"code" => code, "message" => message}} ->
          {:halt, {:error, "RPC error (code #{code}): #{message}"}}

        {:error, reason} ->
          {:halt, {:error, "Failed to fetch transaction: #{inspect(reason)}"}}

        unexpected ->
          {:halt, {:error, "Unexpected response: #{inspect(unexpected)}"}}
      end
    end)
    |> case do
      {:ok, transactions} -> {:ok, Enum.reverse(transactions)}
      error -> error
    end
  end

  defp decode_transactions(transactions) do
    decoded =
      Enum.map(transactions, fn tx ->
        require IEx
        # decoded = ExSolana.RPC.TransactionDecoder.decode(tx)
        IEx.pry()
        IO.inspect(tx, label: "tx")
        # with {:ok, decoded_txn} <- ExSolana.Decoder.TxnDecoder.decode(tx),
        #      {:ok, parsed_txn} <- ExSolana.Decoder.TxnParser.parse(decoded_txn) do
        # %ExSolana.Wallet.Transaction{
        #   signature: tx["transaction"]["signatures"] |> List.first(),
        #   slot: tx["slot"],
        #   err: tx["meta"]["err"],
        #   block_time: tx["blockTime"],
        #   transaction: decode_transaction_info(tx["transaction"])
        # }
        # end
      end)

    {:ok, decoded}
  end

  def portfolio(wallet) do
    rpc_client = ExSolana.rpc_client()

    {:ok, wallet} = update_sol_balance(wallet)

    requests = [
      ExSolana.RPC.Request.get_balance(wallet.address),
      ExSolana.RPC.Request.get_token_accounts_by_owner(wallet.address, encoding: "jsonParsed")
    ]

    [ok: sol_balance, ok: token_accounts] = RPC.send(rpc_client, requests)

    token_addresses =
      Enum.map(token_accounts, fn account ->
        account["account"]["data"]["parsed"]["info"]["mint"]
      end) ++ [B58.encode58(ExSolana.sol())]

    {:ok, %{"data" => prices}} = ExSolana.Jup.price_v2(token_addresses)

    sol_lamports_per_sol = ExSolana.lamports_per_sol()
    sol_balance_in_sol = Decimal.div(Decimal.new(sol_balance), Decimal.new(sol_lamports_per_sol))
    sol_price = Decimal.new(prices[B58.encode58(ExSolana.sol())]["price"])
    sol_value = Decimal.mult(sol_balance_in_sol, sol_price)

    token_balances =
      Enum.map(token_accounts, fn account ->
        mint = account["account"]["data"]["parsed"]["info"]["mint"]

        amount =
          Decimal.new(
            account["account"]["data"]["parsed"]["info"]["tokenAmount"]["uiAmountString"]
          )

        price = Decimal.new(prices[mint]["price"])
        value = Decimal.mult(amount, price)

        %{
          mint: mint,
          amount: amount,
          price: price,
          value: value
        }
      end)

    total_value =
      Enum.reduce(token_balances, sol_value, fn data, acc ->
        Decimal.add(acc, data.value)
      end)

    %{
      address: wallet.address,
      sol_balance: sol_balance_in_sol,
      sol_value: sol_value,
      tokens: token_balances,
      total_value: total_value
    }
  end
end
