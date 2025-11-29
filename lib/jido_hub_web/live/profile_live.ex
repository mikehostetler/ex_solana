defmodule JidoHubWeb.ProfileLive do
  @moduledoc """
  LiveView for displaying user and organization profiles.

  Handles both `/:slug` routes with automatic resolution to User or Organization.
  """

  use JidoHubWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    case socket.assigns[:slug_entity] do
      {:user, user} ->
        {:ok, assign(socket, page_title: user.username, entity_type: :user, entity: user)}

      {:org, org} ->
        {:ok, assign(socket, page_title: org.name, entity_type: :org, entity: org)}

      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Profile not found")
         |> redirect(to: "/")}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <%= case @entity_type do %>
        <% :user -> %>
          <.user_profile user={@entity} current_user={@current_user} />
        <% :org -> %>
          <.org_profile org={@entity} current_user={@current_user} />
      <% end %>
    </div>
    """
  end

  def render(%{live_action: :workflows} = assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold mb-6">
        {if @entity_type == :user, do: @entity.username, else: @entity.name}'s Workflows
      </h1>
      <p class="text-gray-600">Workflow list coming soon...</p>
    </div>
    """
  end

  def render(%{live_action: :settings} = assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold mb-6">Settings</h1>
      <%= case @entity_type do %>
        <% :user -> %>
          <p class="text-gray-600">User settings coming soon...</p>
        <% :org -> %>
          <p class="text-gray-600">Organization settings coming soon...</p>
      <% end %>
    </div>
    """
  end

  defp user_profile(assigns) do
    ~H"""
    <div class="max-w-4xl">
      <div class="flex items-center gap-6 mb-8">
        <div class="w-24 h-24 bg-gray-300 rounded-full flex items-center justify-center text-3xl font-bold text-gray-700">
          {String.first(@user.username) |> String.upcase()}
        </div>
        <div>
          <h1 class="text-4xl font-bold mb-2">{@user.username}</h1>
          <p class="text-gray-600">{@user.email}</p>
        </div>
      </div>

      <div class="space-y-4">
        <div class="border-t pt-4">
          <h2 class="text-xl font-semibold mb-4">About</h2>
          <p class="text-gray-700">
            User profile information will be displayed here.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp org_profile(assigns) do
    ~H"""
    <div class="max-w-4xl">
      <div class="flex items-center gap-6 mb-8">
        <div class="w-24 h-24 bg-blue-500 rounded-lg flex items-center justify-center text-3xl font-bold text-white">
          {String.first(@org.name) |> String.upcase()}
        </div>
        <div>
          <h1 class="text-4xl font-bold mb-2">{@org.name}</h1>
          <p class="text-gray-600">@{@org.slug}</p>
        </div>
      </div>

      <div class="space-y-4">
        <div class="border-t pt-4">
          <h2 class="text-xl font-semibold mb-4">About</h2>
          <p class="text-gray-700">
            Organization profile information will be displayed here.
          </p>
        </div>
      </div>
    </div>
    """
  end
end
