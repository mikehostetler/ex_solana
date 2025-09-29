defmodule ExSolana.Program.IDLMacros.GenerateIXDecoders do
  @moduledoc false
  alias ExSolana.Program.IDLMacros.Helpers

  defmacro generate_ix_decoders(idl) do
    quote bind_quoted: [idl: idl], location: :keep do
      use ExSolana.Util.DebugTools, debug_enabled: false

      require Logger

      if Enum.empty?(idl.instructions || []) do
        nil
      else
        @instructions for ix <- idl.instructions || [],
                          into: %{},
                          do: {ix.discriminator, String.to_atom(Macro.underscore(ix.name))}

        @doc """
        Returns a map of instruction discriminants to their corresponding atom names.

        ## Example

            iex> #{__MODULE__}.instructions()
            %{0 => :initialize, 1 => :transfer, ...}
        """
        def instructions, do: @instructions

        @doc """
        Decodes a single instruction for the program.

        ## Parameters

          * `data` - Binary data of the instruction

        ## Returns

          * `{instruction_type, params}` where:
            * `instruction_type` is an atom representing the type of instruction
            * `params` is a map of decoded parameters for the instruction

        ## Example

            iex> #{__MODULE__}.decode_ix(<<0, ...>>)
            {:initialize, %{...}}
        """
        def decode_ix(data) do
          debug("Decoding instruction", data: Base.encode16(data))

          result =
            case data do
              <<discriminator::binary-size(8), rest::binary>> ->
                discriminator_list = :binary.bin_to_list(discriminator)
                instruction_type = @instructions[discriminator_list]

                debug("Identified instruction type",
                  type: instruction_type,
                  discriminator: discriminator_list
                )

                if instruction_type do
                  apply(__MODULE__, String.to_atom("decode_ix_#{instruction_type}"), [rest])
                else
                  debug("Unknown instruction discriminator", discriminator: discriminator_list)
                  {:unknown_ix, %{data: data}}
                end

              _ ->
                debug("Unknown instruction format - insufficient data for discriminator", data: Base.encode16(data))
                {:unknown_ix, %{data: data}}
            end

          debug("Instruction decoded", result: result)
          result
        end

        # Generate decode_ix_$name functions for each instruction
        for ix <- idl.instructions || [] do
          ix_name = String.to_atom(Macro.underscore(ix.name))

          field_pattern = Helpers.generate_field_pattern(ix.args)

          @doc """
          Decodes a #{ix.name} instruction.

          ## Parameters

            * `data` - Binary data of the instruction

          ## Returns

            * `{:#{ix_name}, decoded_fields}` on success
            * `{:error, :decode_failed}` on failure

          ## Fields

          #{Enum.map_join(ix.args, "\n", fn arg -> "  * `#{arg.name}` - #{inspect(arg.type)}" end)}

          ## Example

              iex> #{__MODULE__}.decode_ix_#{ix_name}(<<...>>)
              {:#{ix_name}, %{...}}
          """
          def unquote(:"decode_ix_#{ix_name}")(data) do
            debug("Decoding #{unquote(ix_name)} instruction", data: Base.encode16(data))

            try do
              {decoded_fields, rest} =
                ExSolana.BinaryDecoder.decode(data, unquote(Macro.escape(field_pattern)))

              result = {unquote(ix_name), decoded_fields}
              debug("Successfully decoded #{unquote(ix_name)} instruction", result: result)
              result
            rescue
              e ->
                error("Failed to decode #{unquote(ix_name)} instruction",
                  instruction: unquote(ix_name),
                  data: Base.encode16(data),
                  error: inspect(e)
                )

                {:error, :decode_failed}
            end
          end

          defoverridable [{:"decode_ix_#{ix_name}", 1}]
        end
      end
    end
  end
end
