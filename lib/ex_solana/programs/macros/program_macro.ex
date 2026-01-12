defmodule ExSolana.Program.IDLMacros do
  @moduledoc false
  defmacro generate_constants(idl) do
    quote do
      alias ExSolana.Program.IDLMacros.GenerateConstants

      require GenerateConstants

      GenerateConstants.generate_constants(unquote(idl))
    end
  end

  defmacro generate_event_decoders(idl, log_prefix) do
    quote do
      alias ExSolana.Program.IDLMacros.GenerateEventDecoders

      require GenerateEventDecoders

      GenerateEventDecoders.generate_event_decoders(
        unquote(idl),
        unquote(log_prefix)
      )
    end
  end

  defmacro generate_ix_creators(idl) do
    quote do
      alias ExSolana.Program.IDLMacros.GenerateIXCreators

      require GenerateIXCreators

      GenerateIXCreators.generate_ix_creators(unquote(idl))
    end
  end

  defmacro generate_ix_decoders(idl) do
    quote do
      alias ExSolana.Program.IDLMacros.GenerateIXDecoders

      require GenerateIXDecoders

      GenerateIXDecoders.generate_ix_decoders(unquote(idl))
    end
  end

  defmacro generate_invocation_analyzers(idl) do
    quote do
      alias ExSolana.Program.IDLMacros.GenerateInvocationAnalyzers

      require GenerateInvocationAnalyzers

      GenerateInvocationAnalyzers.generate_invocation_analyzers(unquote(idl))
    end
  end

  defmacro generate_account_decoders(idl) do
    quote do
      alias ExSolana.Program.IDLMacros.GenerateAccountDecoders

      require GenerateAccountDecoders

      GenerateAccountDecoders.generate_account_decoders(unquote(idl))
    end
  end
end
