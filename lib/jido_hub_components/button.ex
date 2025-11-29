defmodule JidoHubComponents.Button do
  @moduledoc """
  Primary action button component tuned for Jido Hub styling.
  """

  use JidoHubComponents, :component

  alias JidoHubComponents.Utils

  @default_variant "solid"
  @variants ~w(solid outline ghost soft)

  attr :class, :any, default: nil
  attr :size, :string, values: Utils.sizes(), default: "md"
  attr :intent, :string, values: Utils.intents(), default: "primary"
  attr :variant, :string, values: @variants, default: @default_variant
  attr :loading, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :full_width, :boolean, default: false
  attr :type, :string, default: nil

  attr :rest, :global,
    include: ~w(form href type navigate patch method rel target download name value)

  slot :inner_block
  slot :leading_icon
  slot :trailing_icon

  def button(assigns) do
    assigns =
      assigns
      |> assign(:leading_icon?, Utils.slot_present?(assigns.leading_icon))
      |> assign(:trailing_icon?, Utils.slot_present?(assigns.trailing_icon))
      |> assign(
        :class,
        Utils.classes([
          "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-xl border font-medium outline-none transition focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-primary/50 disabled:cursor-not-allowed disabled:opacity-60",
          size_class(assigns.size),
          intent_class(assigns.intent, assigns.variant),
          variant_class(assigns.variant),
          Utils.maybe_add_class(assigns.full_width, "w-full"),
          Utils.maybe_add_class(assigns.loading, "relative"),
          assigns.class
        ])
      )
      |> assign(:type, assigns.type || button_type(assigns))

    ~H"""
    <button class={@class} type={@type} disabled={@disabled or @loading} {@rest}>
      <span :if={@loading} class="absolute inset-0 flex items-center justify-center">
        <span class="size-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
      </span>

      <span :if={@leading_icon?} class="flex items-center">
        {render_slot(@leading_icon)}
      </span>

      <span class={[
        "flex items-center transition",
        Utils.maybe_add_class(@loading, "opacity-0")
      ]}>
        <%= if Utils.slot_present?(@inner_block) do %>
          {render_slot(@inner_block)}
        <% end %>
      </span>

      <span :if={@trailing_icon?} class="flex items-center">
        {render_slot(@trailing_icon)}
      </span>
    </button>
    """
  end

  defp intent_class(intent, "solid") do
    case intent do
      "primary" -> "bg-primary text-primary-content border-transparent hover:bg-primary/90"
      "neutral" -> "bg-slate-900 text-white border-transparent hover:bg-slate-800"
      "info" -> "bg-sky-600 text-white border-transparent hover:bg-sky-500"
      "success" -> "bg-emerald-600 text-white border-transparent hover:bg-emerald-500"
      "warning" -> "bg-amber-500 text-slate-950 border-transparent hover:bg-amber-400"
      "danger" -> "bg-rose-600 text-white border-transparent hover:bg-rose-500"
      _ -> "bg-primary text-primary-content border-transparent"
    end
  end

  defp intent_class(intent, "outline") do
    case intent do
      "primary" -> "border-primary text-primary hover:bg-primary/10"
      "neutral" -> "border-slate-400 text-slate-900 hover:bg-slate-100"
      "info" -> "border-sky-500 text-sky-600 hover:bg-sky-50"
      "success" -> "border-emerald-500 text-emerald-600 hover:bg-emerald-50"
      "warning" -> "border-amber-500 text-amber-600 hover:bg-amber-50"
      "danger" -> "border-rose-500 text-rose-600 hover:bg-rose-50"
      _ -> "border-primary text-primary"
    end
  end

  defp intent_class(intent, "ghost") do
    case intent do
      "primary" -> "border-transparent text-primary hover:bg-primary/10"
      "neutral" -> "border-transparent text-slate-900 hover:bg-slate-100"
      "info" -> "border-transparent text-sky-600 hover:bg-sky-50"
      "success" -> "border-transparent text-emerald-600 hover:bg-emerald-50"
      "warning" -> "border-transparent text-amber-600 hover:bg-amber-50"
      "danger" -> "border-transparent text-rose-600 hover:bg-rose-50"
      _ -> "border-transparent text-primary hover:bg-primary/10"
    end
  end

  defp intent_class(intent, "soft") do
    case intent do
      "primary" -> "border-transparent bg-primary/10 text-primary hover:bg-primary/20"
      "neutral" -> "border-transparent bg-slate-200 text-slate-900 hover:bg-slate-300"
      "info" -> "border-transparent bg-sky-100 text-sky-600 hover:bg-sky-200"
      "success" -> "border-transparent bg-emerald-100 text-emerald-600 hover:bg-emerald-200"
      "warning" -> "border-transparent bg-amber-100 text-amber-700 hover:bg-amber-200"
      "danger" -> "border-transparent bg-rose-100 text-rose-600 hover:bg-rose-200"
      _ -> "border-transparent bg-primary/10 text-primary"
    end
  end

  defp variant_class("outline"), do: "bg-white"
  defp variant_class("ghost"), do: "bg-transparent"
  defp variant_class("soft"), do: "bg-transparent"
  defp variant_class(_variant), do: nil

  defp size_class("xs"), do: "h-8 px-3 text-xs"
  defp size_class("sm"), do: "h-9 px-4 text-sm"
  defp size_class("md"), do: "h-10 px-5 text-sm"
  defp size_class("lg"), do: "h-12 px-6 text-base"
  defp size_class("xl"), do: "h-14 px-8 text-lg"
  defp size_class(_), do: "h-10 px-5 text-sm"

  defp button_type(%{rest: %{href: _}}), do: nil
  defp button_type(%{rest: %{navigate: _}}), do: nil
  defp button_type(%{rest: %{patch: _}}), do: nil
  defp button_type(%{type: type}) when not is_nil(type), do: type
  defp button_type(_assigns), do: "button"
end
