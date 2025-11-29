defmodule JidoHubComponents do
  @moduledoc """
  Local component library for building the Jido Hub interface.

  This module mirrors the developer experience of the `DaisyUIComponents` package
  while giving us a dedicated surface for tailoring behaviours, theming, and
  interactions that are specific to Jido Hub.

  By default, `use JidoHubComponents` imports the foundational component set so it
  can be dropped into LiveViews, function components, or HEEx templates without
  any additional aliases.
  """

  @doc false
  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(helpers())
    end
  end

  @doc false
  def component do
    quote do
      use Phoenix.Component

      unquote(helpers())
    end
  end

  defp helpers do
    quote do
      import JidoHubComponents.JSHelpers
      import JidoHubComponents.Utils

      alias Phoenix.LiveView.JS
    end
  end

  @doc """
  Imports the Jido Hub component collection.

  ## Options

    * `:core_components` - when `true` (default) the core UI primitives are imported.
      Pass `false` if you want to opt out of the default set and cherry pick explicit imports.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end

  defmacro __using__(opts) do
    core_components = Keyword.get(opts, :core_components, true)

    quote do
      import JidoHubComponents.JSHelpers
      import JidoHubComponents.Utils

      unquote(
        if core_components do
          quote do
            import JidoHubComponents.Badge
            import JidoHubComponents.Button
            import JidoHubComponents.Card
          end
        end
      )
    end
  end
end
