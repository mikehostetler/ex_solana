defmodule ExSolana.Program.IDLMacros.GenerateConstants do
  @moduledoc false
  defmacro generate_constants(idl) do
    quote bind_quoted: [idl: idl] do
      require Logger

      @doc """
      Returns a map of error codes to tuples containing the error name (as an atom) and error message.

      ## Available Errors

      #{Enum.map_join(idl.errors || [], "\n", fn error -> "  - `#{inspect(String.to_atom(Macro.underscore(error.name)))}` (code: #{error.code}): #{error.msg || "No message available."}" end)}

      ## Example

          iex> #{inspect(__MODULE__)}.errors()
          %{#{Enum.map_join(idl.errors || [], ", ", fn error -> "#{error.code} => {#{inspect(String.to_atom(Macro.underscore(error.name)))}, #{inspect(error.msg)}}" end)}}
      """
      @errors for error <- idl.errors || [],
                  into: %{},
                  do: {error.code, {String.to_atom(Macro.underscore(error.name)), error.msg}}
      def errors, do: @errors

      @doc """
      Returns a map of additional constants defined in the IDL.

      ## Available Constants

      #{Enum.map_join(idl.constants || [], "\n", fn constant -> "  - `#{inspect(String.to_atom(Macro.underscore(constant.name)))}`: #{inspect(constant.value)}" end)}

      ## Example

          iex> #{inspect(__MODULE__)}.constants()
          %{#{Enum.map_join(idl.constants || [], ", ", fn constant -> "#{inspect(String.to_atom(Macro.underscore(constant.name)))} => #{inspect(constant.value)}" end)}}
      """
      @constants for constant <- idl.constants || [],
                     into: %{},
                     do: {String.to_atom(Macro.underscore(constant.name)), constant.value}
      def constants, do: @constants
    end
  end
end
