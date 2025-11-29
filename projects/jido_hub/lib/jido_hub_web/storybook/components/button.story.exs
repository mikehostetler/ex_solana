defmodule JidoHubWeb.Storybook.Components.Button do
  use PhoenixStorybook.Story, :component

  def function, do: &JidoHubWeb.CoreComponents.button/1

  def imports, do: [{JidoHubWeb.CoreComponents, [icon: 1]}]

  def variations do
    [
      %Variation{
        id: :primary,
        attributes: %{
          variant: "primary"
        },
        slots: [
          "Primary Button"
        ]
      },
      %Variation{
        id: :secondary,
        attributes: %{
          variant: "secondary"
        },
        slots: [
          "Secondary Button"
        ]
      },
      %Variation{
        id: :with_icon,
        attributes: %{
          variant: "primary"
        },
        slots: [
          ~s(<.icon name="hero-heart" class="w-5 h-5" /> With Icon)
        ]
      }
    ]
  end
end
