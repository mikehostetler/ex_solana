defmodule JidoHubWeb.Admin.OrganizationLive.FormComponent do
  @moduledoc """
  Form component for editing organizations in admin panel.
  """
  use JidoHubWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@form}
        id={"organization-form-#{@id}"}
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="space-y-4">
          <.input field={@form[:name]} type="text" label="Name" required />
          <.input field={@form[:description]} type="textarea" label="Description" />
          <.input field={@form[:owner_id]} type="text" label="Owner ID (UUID)" />
        </div>

        <div class="mt-6 flex items-center justify-end gap-3">
          <.button
            type="button"
            variant="secondary"
            phx-click={JS.exec("data-cancel", to: "#organization-modal")}
          >
            Cancel
          </.button>
          <.button type="submit" phx-disable-with="Saving...">
            Save Organization
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"organization" => organization_params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, organization_params)
    {:noreply, assign(socket, form: form)}
  end

  @impl true
  def handle_event("save", %{"organization" => organization_params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: organization_params) do
      {:ok, organization} ->
        notify_parent({:saved, organization})

        {:noreply,
         socket
         |> put_flash(:info, "Organization updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
