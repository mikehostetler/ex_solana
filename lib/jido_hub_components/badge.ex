defmodule JidoHubComponents.Badge do
  @moduledoc """
  Small status badge used for decorations, counts, or feature flags.
  """

  use JidoHubComponents, :component

  alias JidoHubComponents.Utils

  attr :class, :any, default: nil
  attr :intent, :string, values: Utils.intents(), default: "neutral"
  attr :variant, :string, values: ~w(solid soft outline), default: "soft"
  attr :rounded, :boolean, default: true
  attr :rest, :global, include: ~w(title)

  slot :inner_block, required: true

  def badge(assigns) do
    assigns =
      assign(
        assigns,
        :class,
        Utils.classes([
          "inline-flex items-center gap-2 border px-2.5 py-1 text-xs font-semibold uppercase tracking-wide leading-tight",
          intent_class(assigns.intent, assigns.variant),
          Utils.maybe_add_class(assigns.rounded, "rounded-full"),
          Utils.maybe_add_class(not assigns.rounded, "rounded-md"),
          assigns.class
        ])
      )

    ~H"""
    <span class={@class} {@rest}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp intent_class(intent, "solid") do
    case intent do
      "primary" -> "bg-primary text-primary-content border-transparent"
      "neutral" -> "bg-slate-900 text-white border-transparent"
      "info" -> "bg-sky-600 text-white border-transparent"
      "success" -> "bg-emerald-600 text-white border-transparent"
      "warning" -> "bg-amber-500 text-slate-950 border-transparent"
      "danger" -> "bg-rose-600 text-white border-transparent"
      _ -> "bg-primary text-primary-content border-transparent"
    end
  end

  defp intent_class(intent, "outline") do
    base = "bg-white"

    variant =
      case intent do
        "primary" -> "border-primary text-primary"
        "neutral" -> "border-slate-300 text-slate-700"
        "info" -> "border-sky-400 text-sky-600"
        "success" -> "border-emerald-400 text-emerald-600"
        "warning" -> "border-amber-400 text-amber-600"
        "danger" -> "border-rose-400 text-rose-600"
        _ -> "border-primary text-primary"
      end

    Utils.classes([base, variant])
  end

  defp intent_class(intent, "soft") do
    case intent do
      "primary" -> "border-transparent bg-primary/10 text-primary"
      "neutral" -> "border-transparent bg-slate-200 text-slate-800"
      "info" -> "border-transparent bg-sky-100 text-sky-600"
      "success" -> "border-transparent bg-emerald-100 text-emerald-600"
      "warning" -> "border-transparent bg-amber-100 text-amber-600"
      "danger" -> "border-transparent bg-rose-100 text-rose-600"
      _ -> "border-transparent bg-primary/10 text-primary"
    end
  end
end
