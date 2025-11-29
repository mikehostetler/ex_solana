defmodule JidoHubWeb.Admin.UserLive.Index do
  @moduledoc """
  A live view to admin users on the platform (edit/suspend/delete).
  """
  use JidoHubWeb, :live_view

  alias JidoHub.Accounts
  alias JidoHub.Accounts.User
  alias JidoHubWeb.AshDataTable

  require Ash.Query

  @data_table_opts [
    default_limit: 50,
    default_order: %{
      order_by: [:id, :inserted_at],
      order_directions: [:asc, :asc]
    },
    filterable: [:id, :username, :email, :is_suspended, :is_deleted, :inserted_at],
    sortable: [:id, :username, :email, :is_suspended, :is_deleted, :inserted_at]
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(JidoHub.PubSub, "users")

    {:ok,
     assign(socket,
       index_params: nil,
       page_title: "Users",
       form: nil,
       base_filters_form:
         build_base_filters_form(%{
           show_is_suspended: false,
           show_is_deleted: false,
           online: false
         })
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
    |> assign_users(params)
    |> assign(
      index_params: params,
      changeset: nil,
      form: nil,
      online_users:
        "users" |> JidoHubWeb.Presence.list() |> Map.keys() |> Enum.map(&String.to_integer/1),
      page_title: "Users"
    )
  end

  def apply_action(socket, :edit, %{"user_id" => id} = params) do
    user =
      User
      |> Ash.get!(id, actor: socket.assigns.current_user, domain: Accounts)

    socket
    |> assign_users(params)
    |> assign(
      index_params: Map.delete(params, "user_id"),
      changeset: nil,
      page_title: "Edit User",
      user: user,
      form:
        AshPhoenix.Form.for_update(user, :admin_update,
          domain: Accounts,
          actor: socket.assigns.current_user
        )
        |> to_form()
    )
  end

  def apply_action(socket, :new, params) do
    socket
    |> assign_users(params)
    |> assign(
      index_params: params,
      changeset: nil,
      page_title: "New User",
      user: %User{},
      form:
        AshPhoenix.Form.for_create(User, :register_with_password,
          domain: Accounts,
          actor: socket.assigns.current_user
        )
        |> to_form()
    )
  end

  @impl true
  def handle_event("toggle_base_filters", %{"base_filters" => base_filters}, socket) do
    socket =
      socket
      |> assign(base_filters_form: build_base_filters_form(base_filters))
      |> assign_users(socket.assigns[:index_params] || %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_filters", %{"filters" => filter_params}, socket) do
    query_params = build_filter_params(socket.assigns.meta, filter_params)
    {:noreply, push_patch(socket, to: ~p"/admin/users?#{query_params}")}
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, patch_back_to_index(socket)}
  end

  @impl true
  def handle_event("suspend_user", params, socket) do
    user =
      User
      |> Ash.get!(params["id"], actor: socket.assigns.current_user, domain: Accounts)

    case Ash.update(user, %{is_suspended: true},
           actor: socket.assigns.current_user,
           domain: Accounts
         ) do
      {:ok, _user} ->
        socket =
          socket
          |> put_flash(:info, "User suspended")
          |> patch_back_to_index()

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_event("undo_suspend_user", params, socket) do
    user =
      User
      |> Ash.get!(params["id"], actor: socket.assigns.current_user, domain: Accounts)

    case Ash.update(user, %{is_suspended: false},
           actor: socket.assigns.current_user,
           domain: Accounts
         ) do
      {:ok, _user} ->
        socket =
          socket
          |> put_flash(:info, "User no longer suspended")
          |> patch_back_to_index()

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_event("delete_user", params, socket) do
    user =
      User
      |> Ash.get!(params["id"], actor: socket.assigns.current_user, domain: Accounts)

    case Ash.update(user, %{is_deleted: true},
           actor: socket.assigns.current_user,
           domain: Accounts
         ) do
      {:ok, _user} ->
        socket =
          socket
          |> put_flash(:info, "User deleted")
          |> patch_back_to_index()

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_event("undo_delete_user", params, socket) do
    user =
      User
      |> Ash.get!(params["id"], actor: socket.assigns.current_user, domain: Accounts)

    case Ash.update(user, %{is_deleted: false},
           actor: socket.assigns.current_user,
           domain: Accounts
         ) do
      {:ok, _user} ->
        socket =
          socket
          |> put_flash(:info, "User no longer deleted")
          |> patch_back_to_index()

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    {
      :noreply,
      socket
      |> handle_leaves(diff.leaves)
      |> handle_joins(diff.joins)
    }
  end

  defp handle_joins(socket, joins) do
    Enum.reduce(joins, socket, fn {user_id, _}, socket ->
      users =
        Enum.map(socket.assigns.users, fn user ->
          if Integer.to_string(user.id) == user_id do
            {_user, online?} = JidoHubWeb.Presence.online_user?(user)
            Map.put(user, :is_online, online?)
          else
            user
          end
        end)

      assign(socket, users: users)
    end)
  end

  defp handle_leaves(socket, leaves) do
    Enum.reduce(leaves, socket, fn {user_id, _}, socket ->
      users =
        Enum.map(socket.assigns.users, fn user ->
          if Integer.to_string(user.id) == user_id do
            {_user, online?} = JidoHubWeb.Presence.online_user?(user)
            Map.put(user, :is_online, online?)
          else
            user
          end
        end)

      assign(socket, users: users)
    end)
  end

  def build_base_filters_form(params \\ %{}) do
    types = %{
      show_is_suspended: :boolean,
      show_is_deleted: :boolean,
      online: :boolean
    }

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> to_form(as: :base_filters)
  end

  defp patch_back_to_index(socket) do
    push_patch(socket, to: ~p"/admin/users?#{socket.assigns[:index_params] || []}")
  end

  defp assign_users(socket, params) do
    query = User

    # Apply base filters
    query =
      if Phoenix.HTML.Form.input_value(socket.assigns.base_filters_form, :show_is_deleted) do
        query
      else
        Ash.Query.filter(query, is_deleted: false)
      end

    query =
      if Phoenix.HTML.Form.input_value(socket.assigns.base_filters_form, :show_is_suspended) do
        query
      else
        Ash.Query.filter(query, is_suspended: false)
      end

    query =
      if Phoenix.HTML.Form.input_value(socket.assigns.base_filters_form, :online) do
        online_user_ids =
          "users" |> JidoHubWeb.Presence.list() |> Map.keys() |> Enum.map(&String.to_integer/1)

        if online_user_ids == [] do
          query
        else
          Ash.Query.filter(query, id: [in: online_user_ids])
        end
      else
        query
      end

    # Use AshDataTable for pagination, sorting, and filtering
    {users, meta} =
      AshDataTable.search(query, params, @data_table_opts, socket.assigns.current_user)

    users = JidoHubWeb.Presence.online_users(users)

    assign(socket, %{users: users, meta: meta})
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

  def user_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-2" id={"user_actions_container_#{@user.id}"}>
      <.icon_button
        phx-click={JS.patch(~p"/admin/users/#{@user}/edit")}
        aria-label="Edit user"
        title="Edit"
      >
        <.icon name="hero-pencil" class="w-4 h-4" />
      </.icon_button>

      <%= if @user.is_suspended do %>
        <.icon_button
          phx-click="undo_suspend_user"
          phx-value-id={@user.id}
          data-confirm="Are you sure?"
          aria-label="Undo suspend"
          title="Undo suspend"
        >
          <.icon name="hero-arrow-uturn-down" class="w-4 h-4" />
        </.icon_button>
      <% else %>
        <.icon_button
          phx-click="suspend_user"
          phx-value-id={@user.id}
          data-confirm={"Are you sure? #{@user.email} will be logged out and unable to sign in."}
          aria-label="Suspend user"
          title="Suspend"
        >
          <.icon name="hero-no-symbol" class="w-4 h-4" />
        </.icon_button>
      <% end %>

      <%= if @user.is_deleted do %>
        <.icon_button
          phx-click="undo_delete_user"
          phx-value-id={@user.id}
          data-confirm="Are you sure?"
          aria-label="Undo delete"
          title="Undo delete"
        >
          <.icon name="hero-check" class="w-4 h-4" />
        </.icon_button>
      <% else %>
        <.icon_button
          phx-click="delete_user"
          phx-value-id={@user.id}
          data-confirm="Are you sure?"
          aria-label="Delete user"
          title="Delete"
          class="text-error hover:bg-error/10"
        >
          <.icon name="hero-trash" class="w-4 h-4" />
        </.icon_button>
      <% end %>
    </div>
    """
  end
end
