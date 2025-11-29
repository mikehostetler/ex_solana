defmodule JidoHubWeb.Admin.OrganizationLive.Index do
  @moduledoc """
  A live view to admin organizations on the platform (view/edit/delete).
  """
  use JidoHubWeb, :live_view

  alias JidoHub.Organizations
  alias JidoHub.Organizations.Organization
  alias JidoHubWeb.AshDataTable

  require Ash.Query

  @data_table_opts [
    default_limit: 50,
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    },
    filterable: [:id, :name, :slug, :inserted_at],
    sortable: [:id, :name, :slug, :inserted_at]
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       index_params: nil,
       page_title: "Organizations",
       form: nil
     )}
  end

  @impl true
  def handle_params(params, uri, socket) do
    current_path = URI.parse(uri).path
    socket = assign(socket, current_path: current_path)
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def apply_action(socket, :index, params) do
    socket
    |> assign_organizations(params)
    |> assign(
      index_params: params,
      changeset: nil,
      form: nil,
      page_title: "Organizations"
    )
  end

  def apply_action(socket, :edit, %{"organization_id" => id} = params) do
    organization =
      Organization
      |> Ash.Query.for_read(:admin_index)
      |> Ash.Query.load(:owner)
      |> Ash.get!(id, actor: socket.assigns.current_user, domain: Organizations)

    socket
    |> assign_organizations(params)
    |> assign(
      index_params: Map.delete(params, "organization_id"),
      changeset: nil,
      page_title: "Edit Organization",
      organization: organization,
      form:
        AshPhoenix.Form.for_update(organization, :admin_update,
          domain: Organizations,
          actor: socket.assigns.current_user
        )
        |> to_form()
    )
  end

  @impl true
  def handle_event("update_filters", %{"filters" => filter_params}, socket) do
    query_params = build_filter_params(socket.assigns.meta, filter_params)
    {:noreply, push_patch(socket, to: ~p"/admin/organizations?#{query_params}")}
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, patch_back_to_index(socket)}
  end

  @impl true
  def handle_event("delete_organization", params, socket) do
    organization =
      Organization
      |> Ash.get!(params["id"], actor: socket.assigns.current_user, domain: Organizations)

    case Ash.destroy(organization,
           actor: socket.assigns.current_user,
           domain: Organizations
         ) do
      :ok ->
        socket =
          socket
          |> put_flash(:info, "Organization deleted")
          |> assign_organizations(socket.assigns[:index_params] || %{})

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp patch_back_to_index(socket) do
    push_patch(socket, to: ~p"/admin/organizations?#{socket.assigns[:index_params] || []}")
  end

  defp assign_organizations(socket, params) do
    query =
      Organization
      |> Ash.Query.for_read(:admin_index)
      |> Ash.Query.load(:owner)

    # Use AshDataTable for pagination, sorting, and filtering
    {organizations, meta} =
      AshDataTable.search(query, params, @data_table_opts, socket.assigns.current_user)

    assign(socket, %{organizations: organizations, meta: meta})
  end

  defp build_filter_params(meta, filter_params) do
    %{
      "filters" => filter_params,
      "order_by" => Enum.map(meta.order, fn {field, _} -> to_string(field) end),
      "order_directions" => Enum.map(meta.order, fn {_, dir} -> to_string(dir) end),
      "limit" => meta.limit,
      "page" => meta.page
    }
  end

  def organization_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-2" id={"organization_actions_container_#{@organization.id}"}>
      <.icon_button
        phx-click={JS.patch(~p"/admin/organizations/#{@organization}/edit")}
        aria-label="Edit organization"
        title="Edit"
      >
        <.icon name="hero-pencil" class="w-4 h-4" />
      </.icon_button>

      <.icon_button
        phx-click="delete_organization"
        phx-value-id={@organization.id}
        data-confirm="Are you sure? This will permanently delete the organization and all associated data."
        aria-label="Delete organization"
        title="Delete"
        class="text-error hover:bg-error/10"
      >
        <.icon name="hero-trash" class="w-4 h-4" />
      </.icon_button>
    </div>
    """
  end
end
