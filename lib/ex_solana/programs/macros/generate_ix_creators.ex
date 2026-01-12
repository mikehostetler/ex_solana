defmodule ExSolana.Program.IDLMacros.GenerateIXCreators do
  @moduledoc false
  require Logger

  def validate_params(args) do
    quote do
      unquote(
        for arg <- args do
          quote do
            if !Map.has_key?(params, unquote(String.to_atom(arg.name))) do
              raise ArgumentError, "Missing required parameter: #{unquote(arg.name)}"
            end
          end
        end
      )
    end
  end

  def validate_accounts(accounts) do
    quote do
      unquote(
        for account <- accounts do
          quote do
            if !Map.has_key?(params, unquote(String.to_atom(account.name))) do
              raise ArgumentError, "Missing required account: #{unquote(account.name)}"
            end
          end
        end
      )
    end
  end

  def build_ix_data(name, args) do
    quote do
      ExSolana.BinaryUtils.encode_var_bytes([
        # Instruction discriminator (first 8 bytes of the SHA256 hash of the instruction name)
        :binary.part(:crypto.hash(:sha256, unquote(name)), 0, 8),
        # Encoded instruction arguments
        unquote(
          for arg <- args do
            quote do
              ExSolana.BinaryUtils.encode_type(
                params[unquote(String.to_atom(arg.name))],
                unquote(Macro.escape(arg.type))
              )
            end
          end
        )
      ])
    end
  end

  def build_account_metas(accounts) do
    quote do
      [
        unquote(
          for account <- accounts do
            quote do
              %ExSolana.Transaction.AccountMeta{
                pubkey: params[unquote(String.to_atom(account.name))],
                is_signer: unquote(account.isSigner),
                is_writable: unquote(account.isMut)
              }
            end
          end
        )
      ]
    end
  end

  defmacro generate_ix_creators(idl) do
    quote bind_quoted: [idl: idl] do
      require Logger

      for instruction <- idl.instructions do
        name = instruction.name
        args = instruction.args
        accounts = instruction.accounts
        function_name = String.to_atom("ix_#{name}")

        def unquote(function_name)(params) do
          # Validate required parameters
          unquote(validate_params(args))

          # Validate required accounts
          unquote(validate_accounts(accounts))

          # Build the instruction data
          ix_data = unquote(build_ix_data(name, args))

          # Build the account metas
          account_metas = unquote(build_account_metas(accounts))

          {:ok,
           %ExSolana.Transaction.Instruction{
             program_id: id(),
             data: ix_data,
             accounts: account_metas
           }}
        rescue
          e in ArgumentError ->
            Logger.warning("Failed to create #{unquote(name)} instruction: #{inspect(e)}")
            {:error, e.message}
        end
      end

      # Fallback for unknown instructions
      def ix_unknown(name, _params) do
        {:error, "Unknown instruction: #{inspect(name)}"}
      end
    end
  end
end
