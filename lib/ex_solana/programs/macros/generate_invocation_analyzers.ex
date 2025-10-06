defmodule ExSolana.Program.IDLMacros.GenerateInvocationAnalyzers do
  # alias ExSolana.Program.IDLMacros.Helpers
  @moduledoc false
  defmacro generate_invocation_analyzers(idl) do
    quote bind_quoted: [idl: idl], location: :keep do
      use ExSolana.Util.DebugTools, debug_enabled: false

      alias ExSolana.Actions.Unknown

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
        Analyzes an invocation of the program and returns a list of actions.

        ## Parameters

          * `invocation` - A map containing information about the program invocation
          * `decoded_txn` - The decoded transaction containing this invocation

        ## Returns

          * A list of ExSolana.Actions structs representing the analyzed actions

        ## Example

            iex> #{__MODULE__}.analyze_invocation(%{instruction: :transfer, params: %{amount: 1000}}, decoded_txn)
            [%ExSolana.Actions.Unknown{description: "transfer instruction executed", details: %{...}}]
        """
        def analyze_invocation(%{instruction: instruction} = invocation, decoded_txn) do
          debug("Analyzing invocation", invocation: invocation)

          instruction_type = @instructions[instruction]

          case instruction_type do
            nil ->
              analyze_invocation_unknown(invocation, decoded_txn)

            _ ->
              apply(__MODULE__, String.to_atom("analyze_invocation_#{instruction_type}"), [
                invocation,
                decoded_txn
              ])
          end
        end

        # Generate analyzer functions for each instruction
        for ix <- idl.instructions || [] do
          ix_name = String.to_atom(Macro.underscore(ix.name))

          @doc """
          Analyzes a #{ix.name} instruction invocation.

          ## Parameters

            * `invocation` - A map containing information about the program invocation
            * `decoded_txn` - The decoded transaction containing this invocation

          ## Returns

            * A list of ExSolana.Actions structs representing the analyzed actions

          ## Example

              iex> #{__MODULE__}.analyze_invocation_#{ix_name}(%{instruction: :#{ix_name}, params: %{...}}, decoded_txn)
              [%ExSolana.Actions.Unknown{description: "#{ix_name} instruction executed", details: %{...}}]
          """
          def unquote(:"analyze_#{ix_name}")(invocation, decoded_txn) do
            debug("Analyzing #{unquote(ix_name)} invocation", invocation: invocation)

            [
              %Unknown{
                description: "#{unquote(ix_name)} instruction executed",
                details: %{
                  instruction: unquote(ix_name),
                  params: invocation.params
                }
              }
            ]
          end

          defoverridable [{:"analyze_#{ix_name}", 2}]
        end

        # Default analyzer for unknown instructions
        defp analyze_invocation_unknown(invocation, _decoded_txn) do
          debug("Analyzing unknown invocation", invocation: invocation)

          [
            %Unknown{
              description: "Unknown instruction executed",
              program: invocation.program_id,
              details: %{
                instruction: invocation.instruction,
                params: invocation.params
              }
            }
          ]
        end
      end
    end
  end
end
