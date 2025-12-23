defmodule Jido.Character.Persistence.Memory do
  @moduledoc """
  Simple in-memory persistence adapter for characters.

  Uses ETS for storage, keyed by `{module, id}` to support
  multiple character types with the same id.

  This adapter is ephemeral - data is lost when the process stops.
  Use for development, testing, or short-lived sessions.
  """

  @behaviour Jido.Character.Persistence.Adapter

  alias Jido.Character.Definition

  @table __MODULE__

  @impl true
  def save(%Definition{} = defn, %{id: id} = char) when is_binary(id) do
    ensure_table()
    true = :ets.insert(@table, {{defn.module, id}, char})
    {:ok, char}
  end

  def save(%Definition{} = defn, %{"id" => id} = char) do
    save(defn, Map.put(char, :id, id))
  end

  @impl true
  def get(%Definition{} = defn, id) when is_binary(id) do
    ensure_table()

    case :ets.lookup(@table, {defn.module, id}) do
      [{_key, char}] -> {:ok, char}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def delete(%Definition{} = defn, id) when is_binary(id) do
    ensure_table()
    :ets.delete(@table, {defn.module, id})
    :ok
  end

  @doc "Clear all characters from memory. Useful for testing."
  def clear_all do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

      _ref ->
        :ok
    end
  end
end
