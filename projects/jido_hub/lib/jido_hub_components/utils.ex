defmodule JidoHubComponents.Utils do
  @moduledoc false

  @intents ~w(primary neutral info success warning danger)
  @sizes ~w(xs sm md lg xl)

  @doc "Returns the list of intents supported by the component library."
  def intents, do: @intents

  @doc "Returns the supported size tokens."
  def sizes, do: @sizes

  @spec classes(list() | binary() | nil | atom()) :: binary() | nil
  @doc """
  Normalises a collection of classes into a single string.

  Accepts atoms, binaries, or nested lists. Returns `nil` when the input is blank.
  """
  def classes(classes) when is_list(classes) do
    classes
    |> Enum.reduce([], fn class, acc -> [classes(class) | acc] end)
    |> Enum.reverse()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  def classes(nil), do: nil
  def classes(class) when is_atom(class), do: class |> Atom.to_string() |> classes()
  def classes(class) when is_binary(class), do: String.trim(class)
  def classes(class), do: to_string(class)

  @doc "Returns the provided class when the condition is truthy."
  def maybe_add_class(true, class), do: class
  def maybe_add_class("true", class), do: class
  def maybe_add_class(_falsey, _class), do: nil

  @doc "Checks whether a HEEx slot has any content."
  def slot_present?(slot), do: match?([_ | _], slot)

  @doc """
  Utility for composing data attributes while avoiding nil values.
  """
  def data_attributes(attrs) when is_map(attrs) do
    for {key, value} <- attrs, value != nil, into: %{} do
      {"data-#{key}", value}
    end
  end
end
