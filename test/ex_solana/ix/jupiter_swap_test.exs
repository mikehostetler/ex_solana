defmodule ExSolana.Ix.JupiterSwapTest do
  use ExUnit.Case, async: true
  import Mox
  import ExSolana.JupiterTestHelpers

  alias ExSolana.Ix.JupiterSwap
  alias ExSolana.Transaction.Builder

  # Verify on exit that all mocks were called
  setup :verify_on_exit!

  setup do
    # Set mock API key for testing
    Application.put_env(:ex_solana, :jupiter, api_key: "test_api_key")
    :ok
  end

  describe "jupiter_swap/6" do
    test "adds Jupiter swap instructions to builder with defaults" do
      mock_quote = mock_quote_response()
      mock_swap = mock_swap_instructions_response()

      expect(Tesla.Mock, :call, 2, fn
        %{url: url} = env, opts when url =~ "/quote" ->
          # Check query parameters
          query = Keyword.get(opts, :query, [])
          assert query[:inputMint] == test_tokens().sol
          assert query[:outputMint] == test_tokens().usdc
          assert query[:amount] == 1_000_000_000
          assert query[:slippageBps] == 50

          {:ok, %{status: 200, body: mock_quote}}

        %{url: url} = env, opts when url =~ "/swap-instructions" ->
          body = elem(env, 3)[:body]
          assert Map.has_key?(body, :quoteResponse)
          assert Map.has_key?(body, :userPublicKey)

          {:ok, %{status: 200, body: mock_swap}}
      end)

      expect(ExSolana.RPC.Mock, :send, fn _client, _request ->
        # Mock get_multiple_accounts for address lookup tables
        {:ok, %{"result" => %{"value" => []}}}
      end)

      # Create a builder with a mock payer
      mock_payer = ExSolana.pubkey!("MockPayer1111111111111111111111111111111")
      builder = Builder.new() |> Builder.payer(mock_payer)

      tokens = test_tokens()

      assert {:ok, result_builder} =
               JupiterSwap.jupiter_swap(
                 builder,
                 tokens.sol,
                 tokens.usdc,
                 1_000_000_000,
                 50,
                 []
              )

      # Verify instructions were added
      assert length(result_builder.instructions) > 0
    end

    test "validates options using NimbleOptions" do
      builder = Builder.new()
      tokens = test_tokens()

      # Test invalid swap mode
      assert_raise NimbleOptions.ValidationError, ~r/invalid value for :swap_mode/, fn ->
        JupiterSwap.jupiter_swap(
          builder,
          tokens.sol,
          tokens.usdc,
          1_000_000,
          50,
          swap_mode: :InvalidMode
        )
      end
    end

    test "handles quote API errors" do
      expect(Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %{status: 401, body: %{"error" => "Unauthorized"}}}
      end)

      mock_payer = ExSolana.pubkey!("MockPayer1111111111111111111111111111111")
      builder = Builder.new() |> Builder.payer(mock_payer)
      tokens = test_tokens()

      assert {:error, %ExSolana.Jupiter.Errors{}} =
               JupiterSwap.jupiter_swap(
                 builder,
                 tokens.sol,
                 tokens.usdc,
                 1_000_000,
                 50,
                 []
               )
    end

    test "handles swap instructions API errors" do
      mock_quote = mock_quote_response()

      expect(Tesla.Mock, :call, fn
        %{url: url} = env, opts when url =~ "/quote" ->
          {:ok, %{status: 200, body: mock_quote}}

        %{url: url} = env, opts when url =~ "/swap-instructions" ->
          {:ok, %{status: 500, body: %{"error" => "Internal server error"}}}
      end)

      mock_payer = ExSolana.pubkey!("MockPayer1111111111111111111111111111111")
      builder = Builder.new() |> Builder.payer(mock_payer)
      tokens = test_tokens()

      assert {:error, _} =
               JupiterSwap.jupiter_swap(
                 builder,
                 tokens.sol,
                 tokens.usdc,
                 1_000_000,
                 50,
                 []
               )
    end
  end

  describe "parse_instruction/1" do
    test "parses valid instruction with all fields" do
      instruction_json = %{
        "programId" => "Program111111111111111111111111111111111111",
        "accounts" => [
          %{
            "pubkey" => "Account111111111111111111111111111111111111",
            "isSigner" => true,
            "isWritable" => true
          },
          %{
            "pubkey" => "Account222222222222222222222222222222222222",
            "isSigner" => false,
            "isWritable" => false
          }
        ],
        "data" => "base64data"
      }

      instruction = JupiterSwap.parse_instruction(instruction_json)

      assert instruction.program == "Program111111111111111111111111111111111111"
      assert length(instruction.accounts) == 2

      first_account = hd(instruction.accounts)
      assert first_account.key == "Account111111111111111111111111111111111111"
      assert first_account.signer? == true
      assert first_account.writable? == true
    end

    test "parses instruction with empty accounts list" do
      instruction_json = %{
        "programId" => "Program111111111111111111111111111111111111",
        "accounts" => [],
        "data" => ""
      }

      instruction = JupiterSwap.parse_instruction(instruction_json)

      assert instruction.program == "Program111111111111111111111111111111111111"
      assert instruction.accounts == []
    end

    test "handles missing accounts field" do
      instruction_json = %{
        "programId" => "Program111111111111111111111111111111111111",
        "data" => ""
      }

      instruction = JupiterSwap.parse_instruction(instruction_json)

      assert instruction.accounts == []
    end

    test "handles missing isSigner and isWritable fields" do
      instruction_json = %{
        "programId" => "Program111111111111111111111111111111111111",
        "accounts" => [
          %{
            "pubkey" => "Account111111111111111111111111111111111111"
          }
        ],
        "data" => ""
      }

      instruction = JupiterSwap.parse_instruction(instruction_json)

      account = hd(instruction.accounts)
      assert account.signer? == false
      assert account.writable? == false
    end
  end

  describe "NimbleOptions validation" do
    test "accepts valid swap_mode options" do
      builder = Builder.new()
      tokens = test_tokens()

      # These should not raise
      for mode <- [:ExactIn, :ExactOut] do
        # We're not actually calling the API, just testing validation
        # The validation happens inside jupiter_swap, but we can't test it directly
        # without mocking the API calls
        assert {:ok, _} =
                 NimbleOptions.validate(
                   [swap_mode: mode],
                   JupiterSwap |> Module.get_attribute(:jupiter_swap_options)
                 )
      end
    end

    test "accepts valid boolean options" do
      assert {:ok, _} =
               NimbleOptions.validate(
                 [restrict_intermediate_tokens: true, only_direct_routes: false],
                 JupiterSwap |> Module.get_attribute(:jupiter_swap_options)
               )
    end

    test "accepts valid platform_fee_bps" do
      assert {:ok, _} =
               NimbleOptions.validate(
                 [platform_fee_bps: 100],
                 JupiterSwap |> Module.get_attribute(:jupiter_swap_options)
               )
    end

    test "accepts valid max_accounts" do
      assert {:ok, _} =
               NimbleOptions.validate(
                 [max_accounts: 128],
                 JupiterSwap |> Module.get_attribute(:jupiter_swap_options)
               )
    end

    test "accepts valid instruction_version" do
      for version <- [:V1, :V2] do
        assert {:ok, _} =
                 NimbleOptions.validate(
                   [instruction_version: version],
                   JupiterSwap |> Module.get_attribute(:jupiter_swap_options)
                 )
      end
    end

    test "rejects invalid swap_mode" do
      assert_raise NimbleOptions.ValidationError, fn ->
        NimbleOptions.validate(
          [swap_mode: :InvalidMode],
          JupiterSwap |> Module.get_attribute(:jupiter_swap_options)
        )
      end
    end

    test "rejects invalid platform_fee_bps (negative)" do
      assert_raise NimbleOptions.ValidationError, fn ->
        NimbleOptions.validate(
          [platform_fee_bps: -1],
          JupiterSwap |> Module.get_attribute(:jupiter_swap_options)
        )
      end
    end

    test "rejects invalid max_accounts (zero)" do
      assert_raise NimbleOptions.ValidationError, fn ->
        NimbleOptions.validate(
          [max_accounts: 0],
          JupiterSwap |> Module.get_attribute(:jupiter_swap_options)
        )
      end
    end

    test "rejects invalid instruction_version" do
      assert_raise NimbleOptions.ValidationError, fn ->
        NimbleOptions.validate(
          [instruction_version: :V3],
          JupiterSwap |> Module.get_attribute(:jupiter_swap_options)
        )
      end
    end
  end
end
