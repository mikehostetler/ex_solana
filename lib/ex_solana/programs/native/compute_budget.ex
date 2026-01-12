defmodule ExSolana.Native.ComputeBudget do
  @moduledoc """
  Implements the ExSolana.ProgramBehaviour for the ComputeBudget program.
  """

  use ExSolana.ProgramBehaviour,
    program_id: "ComputeBudget11111111111111111111111111111111"

  alias ExSolana.Actions

  require Logger

  @impl true
  def decode_ix(data) do
    case data do
      <<0::unsigned-integer-size(8), units::little-unsigned-integer-size(32)>> ->
        {:request_units, %{units: units}}

      <<1::unsigned-integer-size(8), units::little-unsigned-integer-size(32),
        additional_fee::little-unsigned-integer-size(32)>> ->
        {:request_units_deprecated, %{units: units, additional_fee: additional_fee}}

      <<2::unsigned-integer-size(8), units::little-unsigned-integer-size(32)>> ->
        {:set_compute_unit_limit, %{units: units}}

      <<3::unsigned-integer-size(8), micro_lamports::little-unsigned-integer-size(64)>> ->
        {:set_compute_unit_price, %{micro_lamports: micro_lamports}}

      _ ->
        {:unknown, %{data: data}}
    end
  end

  @impl true
  def analyze_ix(decoded_parsed_ix, _decoded_txn) do
    case decoded_parsed_ix.decoded_ix do
      {:set_compute_unit_price, %{micro_lamports: micro_lamports}} ->
        %Actions.SetComputeUnitPrice{
          micro_lamports: micro_lamports
        }

      {:request_heap_frame, %{bytes: bytes}} ->
        %{
          description: "Request Heap Frame",
          bytes: bytes
        }

      {:set_compute_unit_limit, %{units: units}} ->
        %Actions.SetComputeUnitLimit{
          units: units
        }

      _ ->
        {:unknown_action, %{}}
    end
  end
end
