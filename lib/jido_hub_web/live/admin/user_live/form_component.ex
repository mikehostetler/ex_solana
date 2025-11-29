defmodule JidoHubWeb.Admin.UserLive.FormComponent do
  @moduledoc """
  Form component for creating and editing users in admin panel.
  """
  use JidoHubWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@form}
        id={"user-form-#{@id}"}
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="space-y-4">
          <.input
            field={@form[:username]}
            type="text"
            label="Username"
            required
            aria-label="Username"
          />
          <.input field={@form[:email]} type="email" label="Email" required aria-label="Email" />

          <%= if @action == :new do %>
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              required
              autocomplete="new-password"
            />
            <.input
              field={@form[:password_confirmation]}
              type="password"
              label="Confirm Password"
              required
              autocomplete="new-password"
            />
          <% end %>

          <.input field={@form[:is_suspended]} type="checkbox" label="Suspended" />
          <.input field={@form[:is_deleted]} type="checkbox" label="Deleted" />
          <.input field={@form[:confirmed_at]} type="datetime-local" label="Confirmed At" />
        </div>

        <div class="mt-6 flex items-center justify-end gap-3">
          <.button
            type="button"
            variant="secondary"
            phx-click={JS.exec("data-cancel", to: "#user-modal")}
          >
            Cancel
          </.button>
          <.button type="submit" phx-disable-with="Saving...">
            Save User
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, user_params)
    {:noreply, assign(socket, form: form)}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    save_user(socket, socket.assigns.action, user_params)
  end

  defp save_user(socket, :edit, user_params) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: user_params) do
      {:ok, user} ->
        notify_parent({:saved, user})

        {:noreply,
         socket
         |> put_flash(:info, "User updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp save_user(socket, :new, user_params) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: user_params) do
      {:ok, user} ->
        notify_parent({:saved, user})

        {:noreply,
         socket
         |> put_flash(:info, "User created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
