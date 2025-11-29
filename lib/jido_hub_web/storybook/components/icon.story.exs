defmodule JidoHubWeb.Storybook.Components.Icon do
  use PhoenixStorybook.Story, :component

  def function, do: &JidoHubWeb.CoreComponents.icon/1

  def variations do
    [
      %Variation{
        id: :heart,
        attributes: %{
          name: "hero-heart",
          class: "w-5 h-5"
        }
      }
    ]
  end
end
