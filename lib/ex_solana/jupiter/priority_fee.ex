defmodule ExSolana.Jupiter.PriorityFee do
  @moduledoc """
  Calculate and manage priority fees for Jupiter swaps.

  Jupiter returns compute budget instructions that should be included in the
  transaction to ensure proper execution and faster confirmation.

  Priority Fee = Compute Budget × Compute Unit Price

  ## Examples

  Extract priority fee from Jupiter swap response:

      fees = ExSolana.Jupiter.PriorityFee.from_swap_response(swap_response)
      {:ok, %{compute_budget: 200_000, compute_unit_price: 1_000, total_fee: 200}}

  Estimate fee for custom compute units and price:

      fee = ExSolana.Jupiter.PriorityFee.estimate(1_000_000, 1_000)
      1000

  Create compute budget instructions:

      instructions = ExSolana.Jupiter.PriorityFee.create_instructions(200_000, 1_000)

  """

  alias ExSolana.Native.ComputeBudgetProgram
  alias ExSolana.Instruction

  @type fee_estimate :: %{
          compute_budget: non_neg_integer(),
          compute_unit_price: non_neg_integer(),
          total_fee: non_neg_integer()
        }

  @doc """
  Extract priority fee information from Jupiter swap response.

  Parses the computeBudgetInstructions from Jupiter's response and returns
  the compute budget and unit price.

  ## Parameters

  - `swap_response`: The response from Jupiter's swap-instructions endpoint

  ## Returns

  * `{:ok, fee_estimate}` - Successfully extracted fee information
  * `{:error, reason}` - Failed to parse fee information

  ## Examples

      iex> swap_response = %{
      ...>   "computeBudgetInstructions" => [
      ...>     %{"programId" => "ComputeBudget111111111111111111111111111111", ...}
      ...>   ]
      ...> }
      iex> ExSolana.Jupiter.PriorityFee.from_swap_response(swap_response)
      {:ok, %{compute_budget: 200_000, compute_unit_price: 1_000, total_fee: 200}}

  """
  @spec from_swap_response(map()) :: {:ok, fee_estimate()} | {:error, term()}
  def from_swap_response(swap_response) when is_map(swap_response) do
    compute_budget_instructions = Map.get(swap_response, "computeBudgetInstructions", [])

    case extract_compute_budget(compute_budget_instructions) do
      {:ok, {compute_units, unit_price}} ->
        estimate = %{
          compute_budget: compute_units,
          compute_unit_price: unit_price,
          total_fee: calculate_total_fee(compute_units, unit_price)
        }

        {:ok, estimate}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Estimate priority fee for given compute units and unit price.

  ## Parameters

  - `compute_units`: Number of compute units (e.g., 1_000_000)
  - `unit_price`: Micro-lamports per compute unit (e.g., 1_000)

  ## Returns

  Total fee in lamports

  ## Examples

      iex> ExSolana.Jupiter.PriorityFee.estimate(1_000_000, 1_000)
      1000

      iex> ExSolana.Jupiter.PriorityFee.estimate(200_000, 500)
      100

  """
  @spec estimate(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def estimate(compute_units, unit_price)
      when is_integer(compute_units) and compute_units >= 0 and
           is_integer(unit_price) and unit_price >= 0 do
    calculate_total_fee(compute_units, unit_price)
  end

  @doc """
  Create compute budget instructions for a given priority fee.

  Returns a list of instructions that set the compute unit limit and
  compute unit price.

  ## Parameters

  - `compute_units`: Number of compute units to request
  - `unit_price`: Micro-lamports per compute unit

  ## Returns

  List of `ExSolana.Instruction` structs

  ## Examples

      iex> ExSolana.Jupiter.PriorityFee.create_instructions(200_000, 1_000)
      [%ExSolana.Instruction{...}, %ExSolana.Instruction{...}]

  """
  @spec create_instructions(non_neg_integer(), non_neg_integer()) :: [Instruction.t()]
  def create_instructions(compute_units, unit_price)
      when is_integer(compute_units) and compute_units > 0 and
           is_integer(unit_price) and unit_price >= 0 do
    [
      ComputeBudgetProgram.set_compute_unit_limit(compute_units),
      ComputeBudgetProgram.set_compute_unit_price(unit_price)
    ]
  end

  @doc """
  Suggest compute unit price based on route complexity.

  This is a simplified implementation. In production, you should
  query current network conditions from Solana RPC or Jito.

  ## Returns

  Suggested compute unit price in micro-lamports

  ## Examples

      iex> ExSolana.Jupiter.PriorityFee.suggest_unit_price()
      1000

  """
  @spec suggest_unit_price() :: non_neg_integer()
  def suggest_unit_price do
    # Default to 1,000 micro-lamports per compute unit
    # This is 0.000001 SOL per compute unit
    1_000
  end

  @doc """
  Suggest compute unit limit for a Jupiter swap based on route complexity.

  Jupiter swaps typically require 200,000 - 1,000,000 compute units
  depending on route complexity.

  ## Options

  * `:route_complexity` - `:simple`, `:medium`, `:complex`, or `:very_complex`. Default: `:medium`

  ## Returns

  Suggested compute unit limit

  ## Examples

      iex> ExSolana.Jupiter.PriorityFee.suggest_compute_unit_limit()
      500_000

      iex> ExSolana.Jupiter.PriorityFee.suggest_compute_unit_limit(route_complexity: :simple)
      200_000

  """
  @spec suggest_compute_unit_limit(keyword()) :: non_neg_integer()
  def suggest_compute_unit_limit(opts \\ []) do
    route_complexity = Keyword.get(opts, :route_complexity, :medium)

    case route_complexity do
      :simple -> 200_000
      :medium -> 500_000
      :complex -> 1_000_000
      :very_complex -> 1_400_000
      _ -> 500_000
    end
  end

  @doc """
  Parse compute budget instruction data.

  Extracts compute units or unit price from a compute budget instruction.

  ## Parameters

  - `instruction`: An instruction map from Jupiter's response

  ## Returns

  * `{:set_compute_unit_limit, units}` - Instruction sets compute unit limit
  * `{:set_compute_unit_price, price}` - Instruction sets compute unit price
  * `{:unknown, instruction}` - Unknown instruction type

  """
  @spec parse_instruction(map()) :: {:set_compute_unit_limit, non_neg_integer()}
                                    | {:set_compute_unit_price, non_neg_integer()}
                                    | {:unknown, map()}
  def parse_instruction(%{"programId" => "ComputeBudget111111111111111111111111111111"} = instruction) do
    case decode_instruction_data(instruction) do
      {:ok, {:set_compute_unit_limit, units}} ->
        {:set_compute_unit_limit, units}

      {:ok, {:set_compute_unit_price, price}} ->
        {:set_compute_unit_price, price}

      _ ->
        {:unknown, instruction}
    end
  end

  def parse_instruction(instruction), do: {:unknown, instruction}

  # Private helpers

  # Extract compute units and unit price from Jupiter's compute budget instructions
  defp extract_compute_budget([]) do
    # No compute budget instructions, use defaults
    {:ok, {200_000, 1_000}}
  end

  defp extract_compute_budget(instructions) when is_list(instructions) do
    compute_units = extract_compute_units(instructions)
    unit_price = extract_unit_price(instructions)

    cond do
      compute_units and unit_price ->
        {:ok, {compute_units, unit_price}}

      compute_units ->
        {:ok, {compute_units, 1_000}}

      unit_price ->
        {:ok, {200_000, unit_price}}

      true ->
        {:error, :missing_compute_budget_info}
    end
  end

  defp extract_compute_units(instructions) do
    Enum.find_value(instructions, fn instruction ->
      case parse_instruction(instruction) do
        {:set_compute_unit_limit, units} -> units
        _ -> nil
      end
    end)
  end

  defp extract_unit_price(instructions) do
    Enum.find_value(instructions, fn instruction ->
      case parse_instruction(instruction) do
        {:set_compute_unit_price, price} -> price
        _ -> nil
      end
    end)
  end

  # Decode instruction data based on ComputeBudget program format
  # Format: <discriminator><params>
  # discriminator 2 = set_compute_unit_limit (params: u32)
  # discriminator 3 = set_compute_unit_price (params: u64)
  defp decode_instruction_data(%{"data" => data}) when is_binary(data) do
    case Base.decode64(data) do
      {:ok, decoded} ->
        case decoded do
          <<2::little-unsigned-integer-size(8), units::little-unsigned-integer-size(32)>> ->
            {:ok, {:set_compute_unit_limit, units}}

          <<3::little-unsigned-integer-size(8), price::little-unsigned-integer-size(64)>> ->
            {:ok, {:set_compute_unit_price, price}}

          _ ->
            {:error, :unknown_instruction_format}
        end

      :error ->
        {:error, :invalid_base64}
    end
  end

  defp decode_instruction_data(_), do: {:error, :missing_data}

  # Calculate total fee: compute_units * (unit_price / 1_000_000)
  # Unit price is in micro-lamports, so we divide by 1_000_000
  defp calculate_total_fee(compute_units, unit_price) do
    div(compute_units * unit_price, 1_000_000)
  end
end
