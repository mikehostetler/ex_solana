defmodule JidoHub.Organizations.Invitation.Changes.ValidateInvitationPermissions do
  @moduledoc """
  Validates that the actor has permission to create invitations for the organization.
  Only organization owners and admins can create invitations.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    # Only validate permissions if authorization is enabled
    # If authorize? is false OR no actor is present, skip validation
    authorize? = Map.get(context, :authorize?, true)
    actor = Map.get(context, :actor)
    has_actor? = not is_nil(actor)

    if authorize? and has_actor? do
      with {:ok, organization_id} <- get_organization_id(changeset),
           {:ok, invited_by_id} <- get_invited_by_id(changeset),
           {:ok, actor_id} <- get_actor_id(context),
           true <- actor_id == invited_by_id,
           :ok <- validate_permissions(changeset, organization_id, actor_id) do
        changeset
      else
        {:error, reason} ->
          Ash.Changeset.add_error(changeset, reason)

        false ->
          Ash.Changeset.add_error(changeset, "Actor must match invited_by_id")
      end
    else
      changeset
    end
  end

  defp get_organization_id(changeset) do
    case Ash.Changeset.get_argument(changeset, :organization_id) do
      nil -> {:error, "Organization ID is required"}
      id -> {:ok, id}
    end
  end

  defp get_invited_by_id(changeset) do
    case Ash.Changeset.get_argument(changeset, :invited_by_id) do
      nil -> {:error, "Invited by ID is required"}
      id -> {:ok, id}
    end
  end

  defp get_actor_id(context) do
    case Map.get(context, :actor) do
      %{id: id} -> {:ok, id}
      _ -> {:error, "No authenticated actor found"}
    end
  end

  defp validate_permissions(changeset, organization_id, actor_id) do
    domain = changeset.domain

    # Check if actor is organization owner
    case JidoHub.Organizations.Organization
         |> Ash.Query.filter(id == ^organization_id and owner_id == ^actor_id)
         |> Ash.read_one(domain: domain, authorize?: false) do
      {:ok, %{}} ->
        :ok

      {:ok, nil} ->
        # Not owner, check if admin
        case JidoHub.Organizations.Membership
             |> Ash.Query.filter(
               organization_id == ^organization_id and
                 user_id == ^actor_id and
                 role == :admin
             )
             |> Ash.read_one(domain: domain, authorize?: false) do
          {:ok, %{}} ->
            :ok

          {:ok, nil} ->
            {:error, "User does not have permission to invite others to this organization"}

          {:error, _} ->
            {:error, "Failed to check permissions"}
        end

      {:error, _} ->
        {:error, "Failed to check organization ownership"}
    end
  end
end
