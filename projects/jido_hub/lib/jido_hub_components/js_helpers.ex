defmodule JidoHubComponents.JSHelpers do
  @moduledoc """
  Shared LiveView JS helpers tailored for Jido Hub interactions.
  """

  alias Phoenix.LiveView.JS

  @doc """
  Reveals a target with a soft translate/opacity transition.
  """
  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 250,
      transition:
        {"transition-all ease-out duration-250",
         "opacity-0 translate-y-2 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  @doc """
  Hides a target using a matching transition so animations feel consistent.
  """
  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-2 sm:translate-y-0 sm:scale-95"}
    )
  end
end
