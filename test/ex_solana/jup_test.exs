defmodule ExSolana.JupTest do
  use ExUnit.Case, async: true
  import Mox
  import ExSolana.JupiterTestHelpers

  alias ExSolana.Jup

  # Verify on exit that all mocks were called
  setup :verify_on_exit!

  setup do
    # Set mock API key for testing
    Application.put_env(:ex_solana, :jupiter, api_key: "test_api_key")
    :ok
  end

  describe "client/0" do
    test "creates a Tesla client with proper middleware" do
      client = Jup.client()
      assert is_struct(client, Tesla.Client)
    end

    test "includes API key header when configured" do
      Application.put_env(:ex_solana, :jupiter, api_key: "test_key")
      client = Jup.client()

      # Check that middleware includes Headers
      assert Enum.any?(client.middleware, fn
               {Tesla.Middleware.Headers, _} -> true
               _ -> false
             end)
    end
  end

  describe "price_client/0" do
    test "creates a client for the price API" do
      client = Jup.price_client()
      assert is_struct(client, Tesla.Client)
    end
  end

  describe "token_list_client/0" do
    test "creates a client for the token list API" do
      client = Jup.token_list_client()
      assert is_struct(client, Tesla.Client)
    end
  end

  describe "quote_v1/5" do
    test "returns quote for valid parameters with defaults" do
      # Mock the Tesla client to return a successful response
      mock_response = mock_quote_response()

      expect(Tesla.Mock, :call, fn %{url: url}, _opts ->
        assert url =~ "/quote"

        {:ok, %{status: 200, body: mock_response}}
      end)

      client = Tesla.client([{Tesla.Mock, :call}])
      tokens = test_tokens()

      assert {:ok, quote_response} =
               Jup.quote_v1(client, tokens.sol, tokens.usdc, 1_000_000_000, 50)

      assert quote_response["inputMint"] == tokens.sol
      assert quote_response["outputMint"] == tokens.usdc
    end

    test "handles ExactIn swap mode" do
      mock_response = mock_quote_response(swap_mode: "ExactIn")

      expect(Tesla.Mock, :call, fn %{url: url} = env, _opts ->
        assert url =~ "/quote"
        assert url =~ "swapMode=ExactIn"
        {:ok, %{status: 200, body: mock_response}}
      end)

      client = Tesla.client([{Tesla.Mock, :call}])
      tokens = test_tokens()

      assert {:ok, quote_response} =
               Jup.quote_v1(client, tokens.sol, tokens.usdc, 1_000_000_000, 50, swap_mode: :ExactIn)

      assert quote_response["swapMode"] == "ExactIn"
    end

    test "handles ExactOut swap mode" do
      mock_response = mock_quote_response(swap_mode: "ExactOut")

      expect(Tesla.Mock, :call, fn %{url: url}, _opts ->
        assert url =~ "swapMode=ExactOut"
        {:ok, %{status: 200, body: mock_response}}
      end)

      client = Tesla.client([{Tesla.Mock, :call}])
      tokens = test_tokens()

      assert {:ok, _} =
               Jup.quote_v1(client, tokens.sol, tokens.usdc, 1_000_000, 50, swap_mode: :ExactOut)
    end

    test "applies dexes filter" do
      mock_response = mock_quote_response()

      expect(Tesla.Mock, :call, fn %{url: url}, _opts ->
        assert url =~ "dexes=Orca%2CRaydium"
        {:ok, %{status: 200, body: mock_response}}
      end)

      client = Tesla.client([{Tesla.Mock, :call}])
      tokens = test_tokens()

      assert {:ok, _} =
               Jup.quote_v1(client, tokens.sol, tokens.usdc, 1_000_000_000, 50, dexes: "Orca,Raydium")
    end

    test "applies excludeDexes filter" do
      mock_response = mock_quote_response()

      expect(Tesla.Mock, :call, fn %{url: url}, _opts ->
        assert url =~ "excludeDexes=Serum"
        {:ok, %{status: 200, body: mock_response}}
      end)

      client = Tesla.client([{Tesla.Mock, :call}])
      tokens = test_tokens()

      assert {:ok, _} =
               Jup.quote_v1(client, tokens.sol, tokens.usdc, 1_000_000_000, 50, exclude_dexes: "Serum")
    end

    test "applies only_direct_routes option" do
      mock_response = mock_quote_response()

      expect(Tesla.Mock, :call, fn %{url: url}, _opts ->
        assert url =~ "onlyDirectRoutes=true"
        {:ok, %{status: 200, body: mock_response}}
      end)

      client = Tesla.client([{Tesla.Mock, :call}])
      tokens = test_tokens()

      assert {:ok, _} =
               Jup.quote_v1(client, tokens.sol, tokens.usdc, 1_000_000_000, 50,
                 only_direct_routes: true
               )
    end

    test "applies platform_fee_bps option" do
      mock_response = mock_quote_response()

      expect(Tesla.Mock, :call, fn %{url: url}, _opts ->
        assert url =~ "platformFeeBps=100"
        {:ok, %{status: 200, body: mock_response}}
      end)

      client = Tesla.client([{Tesla.Mock, :call}])
      tokens = test_tokens()

      assert {:ok, _} =
               Jup.quote_v1(client, tokens.sol, tokens.usdc, 1_000_000_000, 50, platform_fee_bps: 100)
    end

    test "returns error for invalid parameters" do
      client = Tesla.client([{Tesla.Mock, :call}])

      # Invalid amount (0)
      assert {:error, "Invalid parameters for quote_v1"} =
               Jup.quote_v1(client, test_tokens().sol, test_tokens().usdc, 0, 50)

      # Invalid amount (negative)
      assert {:error, "Invalid parameters for quote_v1"} =
               Jup.quote_v1(client, test_tokens().sol, test_tokens().usdc, -1_000, 50)

      # Invalid slippage (negative)
      assert {:error, "Invalid parameters for quote_v1"} =
               Jup.quote_v1(client, test_tokens().sol, test_tokens().usdc, 1_000_000, -1)
    end

    test "handles HTTP errors" do
      expect(Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %{status: 401, body: %{"error" => "Unauthorized"}}}
      end)

      client = Tesla.client([{Tesla.Mock, :call}])
      tokens = test_tokens()

      assert {:error, %ExSolana.Jupiter.Errors{reason: :invalid_api_key}} =
               Jup.quote_v1(client, tokens.sol, tokens.usdc, 1_000_000_000, 50)
    end

    test "handles rate limiting" do
      expect(Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %{status: 429, body: %{"error" => "Rate limit exceeded"}}}
      end)

      client = Tesla.client([{Tesla.Mock, :call}])
      tokens = test_tokens()

      assert {:error, %ExSolana.Jupiter.Errors{reason: :rate_limited}} =
               Jup.quote_v1(client, tokens.sol, tokens.usdc, 1_000_000_000, 50)
    end
  end

  describe "swap_instructions/4" do
    test "returns swap instructions for valid quote" do
      mock_swap_response = mock_swap_instructions_response()

      expect(Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %{status: 200, body: mock_swap_response}}
      end)

      client = Tesla.client([{Tesla.Mock, :call}])

      assert {:ok, response} =
               Jup.swap_instructions(client, %{"test" => "quote"}, "user_public_key")

      assert Map.has_key?(response, "swapInstruction")
      assert is_list(response["computeBudgetInstructions"])
    end

    test "handles missing quote response" do
      expect(Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %{status: 400, body: %{"error" => "Invalid quote"}}}
      end)

      client = Tesla.client([{Tesla.Mock, :call}])

      assert {:error, _} = Jup.swap_instructions(client, %{}, "user_public_key")
    end
  end

  describe "calculate_price_impact/1" do
    test "calculates price impact from quote response" do
      quote_response = mock_quote_response(price_impact: "1.5")
      impact = Jup.calculate_price_impact(quote_response)

      assert_in_delta 0.015, impact, 0.001
    end

    test "returns 0 for quote without priceImpactPct" do
      quote_response = %{"test" => "data"}
      impact = Jup.calculate_price_impact(quote_response)

      assert impact == 0.0
    end

    test "returns 0 for invalid price impact format" do
      quote_response = %{"priceImpactPct" => "invalid"}
      impact = Jup.calculate_price_impact(quote_response)

      assert impact == 0.0
    end
  end

  describe "calculate_fees/1" do
    test "calculates total fees from quote response" do
      quote_response = mock_quote_response()
      fees = Jup.calculate_fees(quote_response)

      assert Map.has_key?(fees, :total)
      assert Map.has_key?(fees, :breakdown)
      assert is_list(fees.breakdown)
      assert length(fees.breakdown) > 0

      # Check first breakdown item
      first_fee = hd(fees.breakdown)
      assert Map.has_key?(first_fee, :fee_amount)
      assert Map.has_key?(first_fee, :label)
    end

    test "returns zero fees for empty route plan" do
      quote_response = %{"routePlan" => []}
      fees = Jup.calculate_fees(quote_response)

      assert fees.total == 0
      assert fees.breakdown == []
    end

    test "returns zero fees for quote without route plan" do
      quote_response = %{"test" => "data"}
      fees = Jup.calculate_fees(quote_response)

      assert fees.total == 0
      assert fees.breakdown == []
    end
  end

  describe "price_v2/2" do
    test "returns price for single token" do
      mock_price = mock_price_response([test_tokens().sol])

      expect(Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %{status: 200, body: mock_price}}
      end)

      client = Tesla.client([{Tesla.Mock, :call}])

      assert {:ok, response} = Jup.price_v2(test_tokens().sol)
      assert Map.has_key?(response, "data")
    end

    test "returns prices for multiple tokens" do
      tokens = [test_tokens().sol, test_tokens().usdc]
      mock_price = mock_price_response(tokens)

      expect(Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %{status: 200, body: mock_price}}
      end)

      client = Tesla.client([{Tesla.Mock, :call}])

      assert {:ok, response} = Jup.price_v2(tokens)
      assert Map.has_key?(response, "data")
    end

    test "handles show_extra_info option" do
      mock_price = mock_price_response([test_tokens().sol])

      expect(Tesla.Mock, :call, fn %{url: url}, _opts ->
        assert url =~ "showExtraInfo=true"
        {:ok, %{status: 200, body: mock_price}}
      end)

      client = Tesla.client([{Tesla.Mock, :call}])

      assert {:ok, _} = Jup.price_v2(test_tokens().sol, show_extra_info: true)
    end
  end

  describe "get_token_by_mint/1" do
    test "returns token info for valid mint" do
      mock_tokens = mock_token_list_response()
      token = hd(mock_tokens["tokens"])

      expect(Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %{status: 200, body: token}}
      end)

      client = Tesla.client([{Tesla.Mock, :call}])

      assert {:ok, response} = Jup.get_token_by_mint(test_tokens().sol)
      assert Map.has_key?(response, "address")
      assert Map.has_key?(response, "symbol")
    end

    test "handles unknown mint address" do
      expect(Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %{status: 404, body: %{"error" => "Token not found"}}}
      end)

      client = Tesla.client([{Tesla.Mock, :call}])

      assert {:error, _} = Jup.get_token_by_mint("unknown_mint_address")
    end
  end

  describe "get_tokens_by_tag/1" do
    test "returns tokens for valid tags" do
      mock_tokens = mock_token_list_response()

      expect(Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %{status: 200, body: mock_tokens}}
      end)

      client = Tesla.client([{Tesla.Mock, :call}])

      assert {:ok, response} = Jup.get_tokens_by_tag([:verified, :stablecoin])
      assert Map.has_key?(response, "tokens")
      assert is_list(response["tokens"])
    end

    test "handles invalid tags" do
      client = Tesla.client([{Tesla.Mock, :call}])

      assert {:error, "Invalid tags provided"} = Jup.get_tokens_by_tag([:invalid_tag])
    end
  end

  describe "set_base_url/1" do
    test "sets a valid base URL" do
      assert :ok = Jup.set_base_url("https://custom.jupiter.api")
    end

    test "rejects invalid URL" do
      assert {:error, "Invalid URL format"} = Jup.set_base_url("not-a-url")
    end
  end
end
