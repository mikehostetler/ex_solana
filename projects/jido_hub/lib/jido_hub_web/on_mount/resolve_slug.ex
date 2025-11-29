defmodule JidoHubWeb.OnMount.ResolveSlug do
  @moduledoc """
  LiveView on_mount hooks for resolving dynamic slug routes.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  @dialyzer {:nowarn_function, on_mount: 4}

  @doc """
  Resolves a single `/:slug` route to a User or Organization.

  Assigns `:slug_entity` as `{:user, user}` or `{:org, org}` to the socket.
  """
  def on_mount(:single_slug, %{"slug" => slug}, _session, socket) do
    case JidoHub.Slugs.resolve(slug) do
      {:ok, entity} ->
        {:cont, assign(socket, :slug_entity, entity)}

      {:error, :not_found} ->
        socket =
          socket
          |> put_flash(:error, "Page not found")
          |> redirect(to: "/")

        {:halt, socket}
    end
  end

  def on_mount(
        :owner_pod,
        %{"owner_slug" => owner_slug, "pod_slug" => pod_slug},
        _session,
        socket
      ) do
    case JidoHub.Slugs.resolve_owner_and_pod(owner_slug, pod_slug) do
      {:ok, %{owner: owner, pod: pod}} ->
        socket =
          socket
          |> assign(:owner, owner)
          |> assign(:pod, pod)

        {:cont, socket}

      {:error, :not_found} ->
        socket =
          socket
          |> put_flash(:error, "Pod not found")
          |> redirect(to: "/")

        {:halt, socket}
    end
  end

  def on_mount(_, _params, _session, socket), do: {:cont, socket}
end
