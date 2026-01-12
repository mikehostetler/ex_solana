defmodule ExSolana.Programs.Default do
  @moduledoc """
  Implements a default ExSolana.ProgramBehaviour for unknown programs with enhanced defensive processing.
  """
  use ExSolana.ProgramBehaviour, program_id: "DefaultProgramDecoder"

  # alias ExSolana.Actions
  alias ExSolana.Transaction.Core.Invocation

  require Logger

  @type discriminator :: integer()
  @type instruction_type ::
          :unknown
          | {:discriminator_8, discriminator()}
          | {:discriminator_32, discriminator()}
          | {:discriminator_64, discriminator()}

  @impl true
  def id, do: ExSolana.pubkey!("DefaultProgramDecoder")

  @impl true
  @spec decode_ix(binary()) :: {instruction_type(), map()}
  def decode_ix(data) do
    {instruction_type, remaining_data} = extract_discriminator(data)

    {instruction_type,
     %{
       data: remaining_data,
       hex: Base.encode16(data, case: :lower),
       length: byte_size(data)
     }}
  end

  @impl true
  @spec analyze_invocation(Invocation.t(), map()) :: term()
  def analyze_invocation(_invocation, _decoded_txn) do
    {:unknown_action, %{}}
  end

  @impl true
  @spec analyze_ix(map(), map()) :: term()
  def analyze_ix(_decoded_parsed_ix, _decoded_txn) do
    {:unknown_action, %{}}
  end

  @impl true
  @spec decode_events(list(String.t())) :: nil
  def decode_events(_events), do: nil

  @impl true
  @spec decode_account(map()) :: {:unknown_account, map()}
  def decode_account(account), do: {:unknown_account, account}

  @spec extract_discriminator(binary()) :: {instruction_type(), binary()}
  defp extract_discriminator(data) do
    cond do
      match?({:ok, _}, extract_u8_discriminator(data)) ->
        {:ok, {type, value}} = extract_u8_discriminator(data)
        {type, value}

      match?({:ok, _}, extract_u32_discriminator(data)) ->
        {:ok, {type, value}} = extract_u32_discriminator(data)
        {type, value}

      match?({:ok, _}, extract_u64_discriminator(data)) ->
        {:ok, {type, value}} = extract_u64_discriminator(data)
        {type, value}

      true ->
        log_extraction_failure(data)
        {:unknown, data}
    end
  end

  defp extract_u8_discriminator(<<discriminator::unsigned-integer-size(8), rest::binary>>) do
    if discriminator <= 255 do
      {:ok, {{:discriminator_8, discriminator}, rest}}
    else
      :error
    end
  end

  defp extract_u8_discriminator(_), do: :error

  defp extract_u32_discriminator(
         <<discriminator::little-unsigned-integer-size(32), rest::binary>>
       ) do
    if discriminator <= 1_000_000 do
      {:ok, {{:discriminator_32, discriminator}, rest}}
    else
      :error
    end
  end

  defp extract_u32_discriminator(_), do: :error

  defp extract_u64_discriminator(
         <<discriminator::little-unsigned-integer-size(64), rest::binary>>
       ) do
    if discriminator <= 1_000_000_000_000 do
      {:ok, {{:discriminator_64, discriminator}, rest}}
    else
      :error
    end
  end

  defp extract_u64_discriminator(_), do: :error

  defp log_extraction_failure(data) do
    if byte_size(data) < 8 do
      Logger.warning("Instruction data too short to contain a discriminator",
        data: inspect(data, limit: :infinity, printable_limit: :infinity)
      )
    else
      Logger.warning("Failed to extract discriminator from instruction data",
        data: inspect(data, limit: :infinity, printable_limit: :infinity)
      )
    end
  end

  # defp extract_account_info(accounts) do
  #   Enum.map(accounts, fn account ->
  #     %{
  #       key: account.key,
  #       is_signer: account.signer?,
  #       is_writable: account.writable?
  #     }
  #   end)
  # end
end
