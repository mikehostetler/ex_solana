defmodule ExSolana.TxDecoder do
  @moduledoc false
  use ExSolana.Util.DebugTools, debug_enabled: false

  alias ExSolana.Geyser.SubscribeUpdateTransaction

  @doc """
  Decodes a Solana transaction, extracts actions, and generates human-readable descriptions.
  """
  @spec decode(SubscribeUpdateTransaction.t()) ::
          {:ok, map()} | {:error, String.t()}
  def decode(%SubscribeUpdateTransaction{} = transaction) do
    start_time = System.monotonic_time(:microsecond)

    result =
      with {:ok, parsed_logs} <- parse_logs(transaction),
           {:ok, decoded_txn} <- decode_transaction(transaction),
           {:ok, parsed_ix} <- parse_instructions(decoded_txn, parsed_logs),
           {:ok, analyzed_ix} <- analyze_instructions(parsed_ix, decoded_txn),
           {:ok, %{actions: actions, human_readable: human_readable}} <-
             ExSolana.Decoder.TxnActions.extract(analyzed_ix) do
        # actions = extract_actions(analyzed_ix)
        # human_readable = Enum.map(actions, &to_human_readable/1)
        # actions = []
        # human_readable = []

        {:ok,
         %{
           signature: transaction.transaction.signature,
           slot: transaction.slot,
           parsed_logs: parsed_logs,
           decoded_txn: decoded_txn,
           parsed_ix: parsed_ix,
           analyzed_ix: analyzed_ix,
           actions: actions,
           human_readable: human_readable
         }}
      else
        {:error, reason} ->
          {:error, "Failed to decode transaction: #{reason}"}

        {:error, :action_extraction_failed, e} ->
          {:error, "Failed to extract actions: #{inspect(e)}"}
      end

    end_time = System.monotonic_time(:microsecond)
    duration = end_time - start_time
    debug("Transaction decoding took #{duration} µs")

    result
  end

  defp parse_logs(%{transaction: %{meta: %{log_messages: logs}}}) do
    ExSolana.Decoder.LogParser.parse_logs(logs)
  end

  defp decode_transaction(transaction) do
    ExSolana.Decoder.TxnDecoder.decode(transaction)
  end

  defp parse_instructions(decoded_txn, parsed_logs) do
    ExSolana.Decoder.IxParser.parse(decoded_txn, parsed_logs)
  end

  defp analyze_instructions(parsed_ix, decoded_txn) do
    ExSolana.Decoder.IxAnalyzer.analyze(parsed_ix, decoded_txn)
  end

  #   @moduledoc """
  #   A unified module for decoding and processing Solana transactions from various input formats.
  #   """

  #   alias ExSolana.Decoder.IxAnalyzer
  #   alias ExSolana.Decoder.IxParser
  #   alias ExSolana.Decoder.LogParser
  #   alias ExSolana.Decoder.TxnActions
  #   alias ExSolana.Decoder.TxnDecoder
  #   alias ExSolana.Decoder.TxnFilter
  #   alias ExSolana.Geyser.SubscribeUpdate

  #   require Logger

  #   @type input_type :: :binary | :geyser | :decoded
  #   @type process_result :: {:ok, map()} | {:error, String.t()}

  #   @doc """
  #   Process a Solana transaction from various input types.

  #   ## Parameters

  #   - data: The input data (binary, Geyser struct, or decoded transaction)
  #   - type: The type of input (:binary, :geyser, or :decoded)
  #   - opts: Additional options (e.g., filters for TxnFilter)

  #   ## Returns

  #   `{:ok, processed_data}` or `{:error, reason}`
  #   """
  #   @spec process(any(), input_type(), keyword()) :: process_result()
  #   def process(data, type, opts \\ [])

  #   def process(binary_data, :binary, opts) when is_binary(binary_data) do
  #     case :erlang.binary_to_term(binary_data) do
  #       %SubscribeUpdate{update_oneof: {:transaction, txn}} -> process(txn, :geyser, opts)
  #       decoded_txn -> process(decoded_txn, :decoded, opts)
  #     end
  #   rescue
  #     _ -> {:error, "Invalid binary data"}
  #   end

  #   def process(%SubscribeUpdate{update_oneof: {:transaction, txn}}, :geyser, opts) do
  #     process(txn, :decoded, opts)
  #   end

  #   def process(decoded_txn, :decoded, opts) do
  #     with {:ok, parsed_txn} <- parse_transaction(decoded_txn),
  #          {:ok, analyzed_txn} <- analyze_transaction(parsed_txn),
  #          {:ok, actions} <- extract_actions(analyzed_txn),
  #          {:ok, filtered_actions} <- filter_actions(actions, opts[:filters]) do
  #       {:ok, build_output(decoded_txn, parsed_txn, analyzed_txn, actions, filtered_actions)}
  #     end
  #   end

  #   defp parse_transaction(decoded_txn) do
  #     parsed_logs = LogParser.parse_logs(decoded_txn.transaction.meta.log_messages)
  #     IxParser.parse(decoded_txn, parsed_logs)
  #   end

  #   defp analyze_transaction(parsed_txn) do
  #     IxAnalyzer.analyze(parsed_txn)
  #   end

  #   defp extract_actions(analyzed_txn) do
  #     TxnActions.extract(analyzed_txn)
  #   end

  #   defp filter_actions(actions, nil), do: {:ok, actions}

  #   defp filter_actions(actions, filters) do
  #     TxnFilter.filter(actions.data, filters)
  #   end

  #   defp build_output(decoded_txn, parsed_txn, analyzed_txn, actions, filtered_actions) do
  #     %{
  #       signature: decoded_txn.transaction.signature,
  #       slot: decoded_txn.slot,
  #       parsed_txn: parsed_txn,
  #       analyzed_txn: analyzed_txn,
  #       actions: actions,
  #       filtered_actions: filtered_actions
  #     }
  #   end

  #   @doc """
  #   Decode a raw Solana transaction.

  #   ## Parameters

  #   - data: The raw transaction data

  #   ## Returns

  #   `{:ok, decoded_txn}` or `{:error, reason}`
  #   """
  #   @spec decode(binary()) :: {:ok, map()} | {:error, String.t()}
  #   def decode(data) do
  #     case TxnDecoder.decode(data) do
  #       {:ok, decoded_txn} -> {:ok, decoded_txn}
  #       {:error, reason} -> {:error, "Failed to decode transaction: #{inspect(reason)}"}
  #     end
  #   end

  #   @doc """
  #   Format the processed transaction data for display.

  #   ## Parameters

  #   - data: The processed transaction data

  #   ## Returns

  #   A formatted string representation of the data
  #   """
  #   @spec format_output(map()) :: String.t()
  #   def format_output(data) do
  #     data
  #     |> inspect(pretty: true, limit: :infinity)
  #     |> Makeup.highlight()
  #   end
end
