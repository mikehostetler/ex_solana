# defmodule ExSolana.IDLTest do
#   use ExUnit.Case, async: true
#   alias ExSolana.IDL

#   @sample_idl_path "test/support/sample_idl.json"

#   setup do
#     case IDL.load(@sample_idl_path) do
#       {:ok, idl} ->
#         %{idl: idl}

#       {:error, reason} ->
#         IO.puts("Error loading IDL file: #{inspect(reason)}")
#         :error
#     end
#   end

#   describe "load/1" do
#     test "successfully loads and parses a valid IDL file" do
#       assert {:ok, %IDL{}} = IDL.load(@sample_idl_path)
#     end

#     test "returns an error for non-existent file" do
#       assert {:error, :enoent} = IDL.load("non_existent_file.json")
#     end
#   end

#   describe "from_json/1" do
#     test "creates an IDL struct from valid JSON map", %{idl: idl} do
#       assert %IDL{} = idl
#       assert idl.name == "comprehensive_sample"
#       assert map_size(idl.instructions) == 2
#       assert Map.has_key?(idl.instructions, "initialize")
#       assert Map.has_key?(idl.instructions, "complexOperation")
#       assert map_size(idl.accounts) == 2
#       assert map_size(idl.types) == 4
#     end
#   end

#   describe "generate_module/2" do
#     test "generates a valid Elixir module string", %{idl: idl} do
#       module_string = IDL.generate_module(ComprehensiveSample, idl)
#       assert is_binary(module_string)
#       assert String.contains?(module_string, "defmodule ComprehensiveSample do")
#       assert String.contains?(module_string, "use ExSolana.IDL")
#       assert String.contains?(module_string, "defmodule TokenAccount do")
#       assert String.contains?(module_string, "defmodule UserAccount do")
#       assert String.contains?(module_string, "defmodule OperationSettings do")
#       assert String.contains?(module_string, "defmodule UserSettings do")
#       assert String.contains?(module_string, "defmodule AccountState do")
#       assert String.contains?(module_string, "defmodule OperationMode do")
#     end
#   end

#   describe "parse_instructions/1" do
#     test "correctly parses instructions", %{idl: idl} do
#       assert %{"initialize" => %{index: 0, args: [{"data", "u64"}]}} = idl.instructions

#       assert %{
#                "complexOperation" => %{
#                  index: 1,
#                  args: [
#                    {"amount", "u64"},
#                    {"recipient", "publicKey"},
#                    {"settings", %{"defined" => "OperationSettings"}}
#                  ]
#                }
#              } = idl.instructions
#     end
#   end

#   describe "parse_accounts/1" do
#     test "correctly parses accounts", %{idl: idl} do
#       assert %{
#                "UserAccount" => %{
#                  "owner" => "publicKey",
#                  "data" => "u64",
#                  "settings" => {:defined, "UserSettings"}
#                },
#                "TokenAccount" => %{
#                  "mint" => "publicKey",
#                  "owner" => "publicKey",
#                  "amount" => "u64",
#                  "delegate" => {:option, "publicKey"},
#                  "state" => {:defined, "AccountState"},
#                  "isNative" => "bool",
#                  "delegatedAmount" => "u64",
#                  "closeAuthority" => {:option, "publicKey"}
#                }
#              } = idl.accounts
#     end
#   end

#   describe "parse_types/1" do
#     test "correctly parses types", %{idl: idl} do
#       assert %{
#                "OperationSettings" =>
#                  {:struct, %{"fee" => "u64", "mode" => {:defined, "OperationMode"}}},
#                "UserSettings" =>
#                  {:struct, %{"isActive" => "bool", "tier" => "u8", "lastOperation" => "i64"}},
#                "AccountState" => {:enum, ["Uninitialized", "Initialized", "Frozen"]},
#                "OperationMode" => {:enum, ["Normal", "Fast", "Slow"]}
#              } = idl.types
#     end
#   end
# end
