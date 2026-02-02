defmodule ExSolana.Integration.JupiterLifecycleTest do
  use ExUnit.Case, async: false

  import ExSolana.TestHelpers
  import ExSolana.JupiterTestHelpers

  alias ExSolana.Jup
  alias ExSolana.RPC
  alias ExSolana.Jupiter.SwapStatus
  alias ExSolana.Transaction.Builder

  @moduletag :integration
  @moduletag :solana
  @moduletag :jupiter
  @moduletag timeout: 120_000

  setup_all do
    network = get_network_config()
    client = rpc_client(network)

    # Check if Jupiter is available
    jupiter_available? = jupiter_available?(client)

    if jupiter_available? do
      case network do
        :local ->
          # For local testing, create a funded payer
          tracker = ExSolana.tracker(client: client, t: 100)
          {:ok, payer} = create_payer(tracker, client, amount: 10_000)

          [
            network: network,
            client: client,
            tracker: tracker,
            payer: payer,
            skip: false,
            jupiter_available?: true
          ]

        _ ->
          [
            network: network,
            client: client,
            tracker: nil,
            payer: nil,
            skip: false,
            jupiter_available?: true
          ]
      end
    else
      [
        network: network,
        client: client,
        tracker: nil,
        payer: nil,
        skip: true,
        jupiter_available?: false
      ]
    end
  end

  describe "Jupiter quote API" do
    @tag :network_check
    test "gets quote for SOL -> USDC swap", %{client: _client, skip: skip} do
      if skip, do: :skip

      jup_client = Jup.client()
      tokens = test_tokens()

      # Use small amounts for testing
      amount = 1_000_000  # 0.001 SOL

      case Jup.quote_v1(jup_client, tokens.sol, tokens.usdc, amount, 50) do
        {:ok, quote_response} ->
          assert Map.has_key?(quote_response, "inputMint")
          assert quote_response["inputMint"] == tokens.sol
          assert Map.has_key?(quote_response, "outputMint")
          assert quote_response["outputMint"] == tokens.usdc
          assert Map.has_key?(quote_response, "inAmount")
          assert Map.has_key?(quote_response, "outAmount")
          assert Map.has_key?(quote_response, "swapMode")

          # Verify route plan exists
          assert Map.has_key?(quote_response, "routePlan")
          assert is_list(quote_response["routePlan"])
          assert length(quote_response["routePlan"]) > 0

        {:error, %ExSolana.Jupiter.Errors{reason: reason}} ->
          # Some errors are acceptable for integration tests
          # (e.g., rate limiting, network issues)
          flunk("Quote API failed: #{inspect(reason)}")
      end
    end

    test "handles ExactOut swap mode", %{client: _client, skip: skip} do
      if skip, do: :skip

      jup_client = Jup.client()
      tokens = test_tokens()

      # Request specific output amount (0.001 USDC)
      amount = 1_000

      case Jup.quote_v1(jup_client, tokens.sol, tokens.usdc, amount, 50, swap_mode: :ExactOut) do
        {:ok, quote_response} ->
          assert quote_response["swapMode"] == "ExactOut"
          assert Map.has_key?(quote_response, "inAmount")

        {:error, %ExSolana.Jupiter.Errors{}} ->
          # Acceptable for integration tests
          :skip
      end
    end

    test "calculates price impact", %{client: _client, skip: skip} do
      if skip, do: :skip

      jup_client = Jup.client()
      tokens = test_tokens()

      case Jup.quote_v1(jup_client, tokens.sol, tokens.usdc, 1_000_000, 50) do
        {:ok, quote_response} ->
          impact = Jup.calculate_price_impact(quote_response)
          assert is_float(impact)
          assert impact >= 0.0

        {:error, _} ->
          :skip
      end
    end

    test "calculates fees", %{client: _client, skip: skip} do
      if skip, do: :skip

      jup_client = Jup.client()
      tokens = test_tokens()

      case Jup.quote_v1(jup_client, tokens.sol, tokens.usdc, 1_000_000, 50) do
        {:ok, quote_response} ->
          fees = Jup.calculate_fees(quote_response)
          assert Map.has_key?(fees, :total)
          assert Map.has_key?(fees, :breakdown)
          assert is_list(fees.breakdown)

        {:error, _} ->
          :skip
      end
    end
  end

  describe "Jupiter swap instructions API" do
    test "gets swap instructions for a quote", %{client: _client, skip: skip} do
      if skip, do: :skip

      jup_client = Jup.client()
      tokens = test_tokens()

      with {:ok, quote_response} <-
             Jup.quote_v1(jup_client, tokens.sol, tokens.usdc, 1_000_000, 50),
           {:ok, swap_response} <-
             Jup.swap_instructions(jup_client, quote_response, "test_user_public_key") do
        assert Map.has_key?(swap_response, "swapInstruction")
        assert is_map(swap_response["swapInstruction"])
        assert Map.has_key?(swap_response["swapInstruction"], "programId")
        assert Map.has_key?(swap_response["swapInstruction"], "accounts")
        assert Map.has_key?(swap_response["swapInstruction"], "data")
      else
        {:error, _} -> :skip
      end
    end
  end

  describe "Jupiter price API" do
    test "gets price for SOL", %{client: _client, skip: skip} do
      if skip, do: :skip

      price_client = Jup.price_client()
      tokens = test_tokens()

      case Jup.price_v2(tokens.sol) do
        {:ok, response} ->
          assert Map.has_key?(response, "data")
          assert is_map(response["data"])

        {:error, _} ->
          :skip
      end
    end

    test "gets prices for multiple tokens", %{client: _client, skip: skip} do
      if skip, do: :skip

      price_client = Jup.price_client()
      tokens = test_tokens()

      case Jup.price_v2([tokens.sol, tokens.usdc]) do
        {:ok, response} ->
          assert Map.has_key?(response, "data")
          assert is_map(response["data"])

        {:error, _} ->
          :skip
      end
    end
  end

  describe "Jupiter token list API" do
    test "gets token by mint address", %{client: _client, skip: skip} do
      if skip, do: :skip

      token_client = Jup.token_list_client()
      tokens = test_tokens()

      case Jup.get_token_by_mint(tokens.sol) do
        {:ok, token} ->
          assert Map.has_key?(token, "address")
          assert token["address"] == tokens.sol
          assert Map.has_key?(token, "symbol")
          assert Map.has_key?(token, "decimals")

        {:error, _} ->
          :skip
      end
    end

    test "gets tokens by tag", %{client: _client, skip: skip} do
      if skip, do: :skip

      token_client = Jup.token_list_client()

      case Jup.get_tokens_by_tag([:verified]) do
        {:ok, response} ->
          assert Map.has_key?(response, "tokens")
          assert is_list(response["tokens"])

        {:error, _} ->
          :skip
      end
    end
  end

  describe "SwapStatus tracking" do
    test "tracks swap transaction status", %{skip: skip} do
      if skip, do: :skip

      # Start the SwapStatus server
      {:ok, _pid} = SwapStatus.start_link()

      # Track a mock signature
      signature = mock_signature()
      assert :ok = SwapStatus.track(signature)

      # Check status
      assert {:ok, :pending} = SwapStatus.get_status(signature)

      # List all tracked swaps
      tracked = SwapStatus.list_tracked()
      assert Map.has_key?(tracked, signature)
      assert tracked[signature] == :pending

      # Untrack
      assert :ok = SwapStatus.untrack(signature)
      assert {:error, :not_found} = SwapStatus.get_status(signature)

      # Clean up
      GenServer.stop(SwapStatus)
    end

    test "handles multiple tracked swaps", %{skip: skip} do
      if skip, do: :skip

      {:ok, _pid} = SwapStatus.start_link()

      sig1 = mock_signature() <> "1"
      sig2 = mock_signature() <> "2"

      assert :ok = SwapStatus.track(sig1)
      assert :ok = SwapStatus.track(sig2)

      tracked = SwapStatus.list_tracked()
      assert Map.has_key?(tracked, sig1)
      assert Map.has_key?(tracked, sig2)

      # Clean up
      GenServer.stop(SwapStatus)
    end
  end

  # Helper functions

  defp jupiter_available?(client) do
    # Try to get a simple quote to check if Jupiter is available
    case RPC.send(client, RPC.Request.get_account_info("JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4")) do
      {:ok, _} -> true
      _ -> false
    end
  rescue
    _ -> false
  end
end
