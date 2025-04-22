defmodule ExSolana.IDL.Core do
  @moduledoc """
  Type definitions for Solana IDL structures.

  This module defines the structs and types used to represent
  the parsed Solana IDL in Elixir.
  """

  @type idl :: %__MODULE__{
          version: String.t(),
          name: String.t(),
          instructions: [idl_instruction()],
          accounts: [idl_account_def()],
          errors: [idl_error_code()],
          types: [idl_type_def()],
          events: [idl_event()],
          constants: [idl_constant()],
          metadata: idl_metadata()
        }

  @type idl_instruction :: %{
          name: String.t(),
          discriminator: [integer()],
          docs: [String.t()] | nil,
          accounts: [idl_account()],
          args: [idl_field()]
        }

  @type idl_account_def :: %{
          name: String.t(),
          discriminator: [integer()],
          type: idl_type_def_ty_struct(),
          docs: [String.t()] | nil
        }

  @type idl_error_code :: %{
          code: integer(),
          name: String.t(),
          msg: String.t() | nil
        }

  @type idl_type_def :: %{
          name: String.t(),
          type: idl_type_def_ty()
        }

  @type idl_event :: %{
          name: String.t(),
          discriminator: [integer()],
          fields: [idl_event_field()]
        }

  @type idl_constant :: %{
          name: String.t(),
          type: idl_type(),
          value: String.t()
        }

  @type idl_metadata :: %{
          address: String.t() | nil,
          origin: String.t() | nil,
          chainId: String.t() | nil
        }

  @type idl_account :: %{
          name: String.t(),
          isMut: boolean(),
          isSigner: boolean(),
          docs: [String.t()] | nil,
          optional: boolean() | nil
        }

  @type idl_field :: %{
          name: String.t(),
          type: idl_type()
        }

  @type idl_type_def_ty ::
          idl_type_def_ty_struct() | idl_type_def_ty_enum()

  @type idl_type_def_ty_struct :: %{
          kind: :struct,
          fields: [idl_field()]
        }

  @type idl_type_def_ty_enum :: %{
          kind: :enum,
          name: String.t() | nil,
          variants: [idl_enum_variant()]
        }

  @type idl_enum_variant :: %{
          name: String.t(),
          fields: [idl_field()] | [idl_type()] | nil
        }

  @type idl_type ::
          String.t()
          | %{defined: String.t()}
          | %{option: idl_type()}
          | %{coption: idl_type()}
          | %{vec: idl_type()}
          | %{array: {idl_type(), integer()}}

  @type idl_event_field :: %{
          name: String.t(),
          type: idl_type(),
          index: boolean()
        }

  defstruct [
    :version,
    :name,
    :instructions,
    :accounts,
    :errors,
    :types,
    :events,
    :constants,
    metadata: %{}
  ]
end
