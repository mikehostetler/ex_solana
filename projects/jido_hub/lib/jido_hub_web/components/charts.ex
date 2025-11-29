defmodule JidoHubWeb.Components.Charts do
  @moduledoc """
  Components to wrap javascript charting libraries.
  """
  use Phoenix.Component

  def chart_js(assigns) do
    assigns =
      assigns
      |> assign_new(:unique_id, fn -> Ecto.UUID.generate() end)
      |> assign_new(:class, fn -> "" end)
      |> assign_new(:autocolor, fn -> false end)
      |> assign_new(:canvas_width, fn -> nil end)
      |> assign_new(:canvas_height, fn -> nil end)
      |> assign_new(:y_label_format, fn -> nil end)
      |> assign_new(:event, fn -> nil end)
      |> assign_new(:extra_assigns, fn ->
        assigns_to_attributes(assigns, ~w(
          options
          class
          autocolor
          y_label_format
        )a)
      end)

    ~H"""
    <div
      phx-hook="ChartJsHook"
      id={"chart_js_#{@unique_id}"}
      class={@class}
      {@extra_assigns}
      data-chart-options={Jason.encode!(@options)}
      data-autocolor={"#{@autocolor}"}
      data-y-label-format={@y_label_format}
      data-event={@event}
    >
      <canvas style="height: 100% !important; width: 100% !important;"></canvas>
    </div>
    """
  end
end
