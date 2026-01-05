defmodule ExSolana.Decoder.IxAnalyzer do
  @moduledoc """
  Analyzes decoded Solana transactions to extract additional information and program-specific actions.
  """

  use ExSolana.Util.DebugTools, debug_enabled: false

  alias ExSolana.Transaction.Core

  require IEx

  def analyze(parsed_ixs, decoded_txn) do
    debug("Starting instruction analysis", parsed_ixs: parsed_ixs)

    analysis =
      Enum.map(parsed_ixs, fn parsed_ix ->
        analyze_instruction_recursive(parsed_ix, decoded_txn)
      end)

    {:ok, analysis}
  end

  defp analyze_instruction_recursive(parsed_ix, decoded_txn) do
    children = Map.get(parsed_ix, :children, [])
    analyzed_children = Enum.map(children, &analyze_instruction_recursive(&1, decoded_txn))
    child_analyzed_ix = Map.put(parsed_ix, :children, analyzed_children)
    analyze_instruction(child_analyzed_ix, decoded_txn)
  end

  defp analyze_instruction(parsed_ix, %Core.ConfirmedTransaction{} = decoded_txn) do
    program_module = get_program_module(Map.get(parsed_ix, :program, ""))

    debug("Analyzing instruction",
      instruction_id: Map.get(parsed_ix, :id),
      program: Map.get(parsed_ix, :program)
    )

    # IEx.pry()

    decoded_parsed_ix =
      parsed_ix
      |> Map.put(:decoded_ix, decode_instruction(program_module, Map.get(parsed_ix, :ix)))
      |> Map.put(:event, decode_events(program_module, Map.get(parsed_ix, :logs, [])))

    analyzed_ix =
      try do
        Map.put(
          decoded_parsed_ix,
          :action,
          analyze_ix(program_module, decoded_parsed_ix, decoded_txn)
        )
      rescue
        e ->
          IEx.pry()

          error("Failed to analyze instruction",
            error: inspect(e),
            stacktrace: __STACKTRACE__,
            parsed_ix: decoded_parsed_ix
          )

          decoded_parsed_ix
      end

    debug("Analyzed instruction", analyzed_ix: analyzed_ix)

    # if(parsed_ix.id == 6) do
    #   IEx.pry()
    # end

    analyzed_ix
  rescue
    e ->
      error("Failed to analyze instruction",
        error: inspect(e),
        stacktrace: __STACKTRACE__,
        parsed_ix: parsed_ix
      )

      Map.put(parsed_ix, :error, "Failed to analyze: #{inspect(e)}")
  end

  defp analyze_instruction(parsed_ix, _decoded_txn) do
    error("Failed to analyze instruction", parsed_ix: parsed_ix)

    Map.put(parsed_ix, :error, "Failed to analyze")
  end

  defp get_program_module(program_id) do
    debug("Getting program module", program_id: program_id)
    module = ExSolana.program_lookup(program_id) || ExSolana.Programs.Default
    debug("Program module resolved", program_id: program_id, module: module)
    module
  end

  defp decode_events(program_module, logs) do
    program_module.decode_events(logs)
  rescue
    e ->
      error("Failed to decode events",
        module: program_module,
        error: inspect(e),
        stacktrace: __STACKTRACE__
      )

      nil
  end

  defp decode_instruction(program_module, instruction) do
    program_module.decode_ix(instruction.data)
  rescue
    e ->
      error("Failed to decode instruction",
        module: program_module,
        error: inspect(e),
        stacktrace: __STACKTRACE__
      )

      {:unknown_ix, %{data: instruction.data}}
  end

  defp analyze_ix(program_module, decoded_parsed_ix, decoded_txn) do
    case decoded_parsed_ix.decoded_ix do
      {:unknown_ix, _} ->
        {:unknown_action, %{}}

      _ ->
        program_module.analyze_ix(decoded_parsed_ix, decoded_txn)
    end
  rescue
    e ->
      error("Failed to analyze instruction",
        module: program_module,
        error: inspect(e),
        stacktrace: __STACKTRACE__
      )

      {:unknown_action, %{}}
  end
end
