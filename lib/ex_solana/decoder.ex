defmodule ExSolana.Decoder do
  @moduledoc """
  Provides functionality for decoding Solana account data.
  """

  @doc """
  Decodes the given binary data using the specified decoder module or struct.
  """
  @spec decode(module() | struct(), binary()) :: struct()
  def decode(decoder_module, data) when is_atom(decoder_module) do
    decoder_module.decode(data)
  end

  def decode(%struct_module{} = _struct, data) do
    struct_module.decode(data)
  end
end
