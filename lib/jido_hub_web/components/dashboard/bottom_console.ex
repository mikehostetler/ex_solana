defmodule JidoHubWeb.Dashboard.BottomConsole do
  @moduledoc """
  Bottom console/terminal drawer container.
  Visibility controlled by Alpine.js in parent layout.
  """

  use Phoenix.Component

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def bottom_console(assigns) do
    ~H"""
    <div class={["console-container", @class]} id="console-root" phx-hook="ConsoleTabs">
      {render_slot(@inner_block)}
    </div>
    """
  end
end
