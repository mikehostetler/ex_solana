defmodule ExSolana.Decoder do
  @moduledoc """
  Provides functionality for decoding Solana account data.

  This module serves as a unified interface for decoding various types of
  Solana account data, including program-specific accounts and transaction data.

  ## Example

      # Decode using a decoder module
      {:ok, account_data} = ExSolana.RPC.get_account_info(client, pubkey)
      decoded = ExSolana.Decoder.decode(MyProgram.AccountDecoder, account_data["data"])

      # Decode using a decoder struct
      decoder = %MyProgram.CustomDecoder{options: opts}
      decoded = ExSolana.Decoder.decode(decoder, account_data["data"])

  """

  @typedoc "Decoder module or struct"
  @type decoder :: module() | struct()

  @typedoc "Raw binary data to decode"
  @type data :: binary()

  @typedoc "Decoded struct"
  @type decoded :: struct()

  @doc """
  Decodes the given binary data using the specified decoder module or struct.

  When a module is provided, it must implement a `decode/1` function that takes
  binary data and returns a decoded struct.

  When a struct is provided, its module must implement a `decode/2` function
  that takes the struct and binary data, returning a decoded struct.

  ## Parameters

    * `decoder` - A module atom (e.g., `MyProgram.Account`) or a decoder struct
    * `data` - Binary data to decode (typically from RPC response)

  ## Returns

    * A decoded struct

  ## Examples

      # Using a module
      decoded = ExSolana.Decoder_decode(MyProgram.MintAccount, <<binary>>)

      # Using a struct
      decoder = %MyProgram.CustomDecoder{version: 1}
      decoded = ExSolana.Decoder.decode(decoder, <<binary>>)

  """
  @spec decode(decoder(), data()) :: decoded()
  def decode(decoder_module, data) when is_atom(decoder_module) do
    decoder_module.decode(data)
  end

  def decode(%struct_module{} = _struct, data) do
    struct_module.decode(data)
  end
end
