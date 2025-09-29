defmodule ExSolana.Program.IDLMacros.GenerateAccountDecoders do
  @moduledoc false
  alias ExSolana.Program.IDLMacros.Helpers

  defmacro generate_account_decoders(idl) do
    quote bind_quoted: [idl: idl], location: :keep do
      use ExSolana.Util.DebugTools, debug_enabled: true

      if Enum.empty?(idl.accounts || []) do
        nil
      else
        @accounts for account <- idl.accounts || [],
                      into: %{},
                      do: {account.discriminator, String.to_atom(Macro.underscore(account.name))}

        @doc """
        Returns a map of account discriminants to their corresponding atom names.

        ## Example

            iex> #{__MODULE__}.accounts()
            %{0 => :token_account, 1 => :mint_account, ...}
        """
        def accounts, do: @accounts

        @doc """
        Decodes a single account for the program.

        ## Parameters

          * `data` - Binary data of the account

        ## Returns

          * `{account_type, params}` where:
            * `account_type` is an atom representing the type of account
            * `params` is a map of decoded parameters for the account
          * `{:error, :invalid_account_data}` if the data is invalid

        ## Example

            iex> #{__MODULE__}.decode_account(<<0, ...>>)
            {:token_account, %{...}}
        """
        def decode_account(data) do
          debug("Decoding account", data: Base.encode16(data))

          result =
            case data do
              <<discriminator::binary-size(8), rest::binary>> ->
                discriminator_list = :binary.bin_to_list(discriminator)
                account_type = @accounts[discriminator_list]
                debug("Identified account type", type: account_type, discriminator: discriminator_list)

                if account_type do
                  case apply(__MODULE__, String.to_atom("decode_account_#{account_type}"), [rest]) do
                    {atom, data} -> {:ok, {atom, data}}
                    error -> error
                  end
                else
                  error("Unknown account discriminator", discriminator: discriminator_list)
                  {:error, :invalid_account_data}
                end

              _ ->
                error("Invalid account data structure - insufficient data for discriminator", data: Base.encode16(data))
                {:error, :invalid_account_data}
            end

          debug("Account decoded", result: result)
          result
        end

        # Generate decode_account_$name functions for each account
        for account <- idl.accounts || [] do
          account_name = String.to_atom(Macro.underscore(account.name))

          if account.type do
            field_pattern = Helpers.generate_field_pattern(account.type.fields)

            @doc """
            Decodes a #{account.name} account.

            ## Parameters

              * `data` - Binary data of the account

            ## Returns

              * `{:#{account_name}, decoded_fields}` on success
              * `{:error, :decode_failed}` on failure

            ## Fields

            #{Enum.map_join(account.type.fields, "\n", fn field -> "  * `#{field.name}` - #{inspect(field.type)}" end)}

            ## Example

                iex> #{__MODULE__}.decode_account_#{account_name}(<<...>>)
                {:#{account_name}, %{...}}
            """
            def unquote(:"decode_account_#{account_name}")(data) do
              debug("Decoding #{unquote(account_name)} account", data: Base.encode16(data))

              try do
                {decoded_fields, _rest} =
                  ExSolana.BinaryDecoder.decode(data, unquote(Macro.escape(field_pattern)))

                result = {unquote(account_name), decoded_fields}
                debug("Successfully decoded #{unquote(account_name)} account", result: result)
                result
              rescue
                e ->
                  error("Failed to decode #{unquote(account_name)} account",
                    account: unquote(account_name),
                    data: Base.encode16(data),
                    error: inspect(e)
                  )

                  {:error, :decode_failed}
              end
            end
          else
            @doc """
            Account #{account.name} has no type definition in the IDL.
            This function returns the discriminator-based detection only.
            """
            def unquote(:"decode_account_#{account_name}")(_data) do
              {:error, :no_type_definition}
            end
          end

          defoverridable [{:"decode_account_#{account_name}", 1}]
        end
      end
    end
  end
end
