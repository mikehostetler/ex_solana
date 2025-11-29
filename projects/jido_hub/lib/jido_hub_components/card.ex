defmodule JidoHubComponents.Card do
  @moduledoc """
  Elevated surface container with optional header, media, and footer slots.
  """

  use JidoHubComponents, :component

  alias JidoHubComponents.Utils

  attr :class, :any, default: nil
  attr :padding, :string, values: ~w(none sm md lg), default: "md"
  attr :shadow, :string, values: ~w(none sm md lg xl), default: "md"
  attr :rest, :global

  slot :header
  slot :media
  slot :inner_block
  slot :footer

  def card(assigns) do
    assigns =
      assigns
      |> assign(
        :class,
        Utils.classes([
          "relative flex w-full flex-col overflow-hidden rounded-3xl border border-slate-200 bg-white",
          shadow_class(assigns.shadow),
          assigns.class
        ])
      )
      |> assign(:padding_class, padding_class(assigns.padding))
      |> assign(:header?, Utils.slot_present?(assigns.header))
      |> assign(:media?, Utils.slot_present?(assigns.media))
      |> assign(:footer?, Utils.slot_present?(assigns.footer))

    ~H"""
    <article class={@class} {@rest}>
      <div :if={@header?} class={["flex items-start justify-between gap-3", @padding_class, "pb-0"]}>
        {render_slot(@header)}
      </div>

      <div :if={@media?} class="relative aspect-video overflow-hidden rounded-2xl">
        {render_slot(@media)}
      </div>

      <div class={[
        "flex flex-col gap-4",
        Utils.maybe_add_class(@header?, "pt-4"),
        Utils.maybe_add_class(@media?, "pt-4"),
        @padding_class
      ]}>
        {render_slot(@inner_block)}
      </div>

      <div :if={@footer?} class={["flex items-center justify-end gap-3", @padding_class, "pt-4"]}>
        {render_slot(@footer)}
      </div>
    </article>
    """
  end

  defp padding_class("none"), do: "p-0"
  defp padding_class("sm"), do: "p-4"
  defp padding_class("md"), do: "p-6"
  defp padding_class("lg"), do: "p-8"
  defp padding_class(_), do: "p-6"

  defp shadow_class("none"), do: "shadow-none"
  defp shadow_class("sm"), do: "shadow-sm"
  defp shadow_class("md"), do: "shadow-md"
  defp shadow_class("lg"), do: "shadow-lg"
  defp shadow_class("xl"), do: "shadow-xl"
  defp shadow_class(_), do: "shadow-md"
end
