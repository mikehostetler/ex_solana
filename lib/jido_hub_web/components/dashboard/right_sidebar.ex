defmodule JidoHubWeb.Dashboard.RightSidebar do
  use Phoenix.Component

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def right_sidebar(assigns) do
    ~H"""
    <aside class={["flex flex-col h-full", @class]}>
      {render_slot(@inner_block)}
    </aside>
    """
  end
end
