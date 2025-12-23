defmodule Jido.Character.Persistence.Adapter do
  @moduledoc """
  Behaviour for character persistence adapters.

  Adapters provide storage capabilities for characters. The default
  Memory adapter uses ETS for simple, in-memory storage.

  ## Implementing an Adapter

  Implement the three callbacks: `save/2`, `get/2`, and `delete/2`.
  Each receives a `Definition` struct and the character/id.
  """

  alias Jido.Character.Definition

  @doc "Save a character. Returns {:ok, character} or {:error, reason}."
  @callback save(Definition.t(), map()) :: {:ok, map()} | {:error, term()}

  @doc "Get a character by id. Returns {:ok, character} or {:error, :not_found}."
  @callback get(Definition.t(), String.t()) :: {:ok, map()} | {:error, :not_found | term()}

  @doc "Delete a character by id. Returns :ok or {:error, reason}."
  @callback delete(Definition.t(), String.t()) :: :ok | {:error, term()}
end
