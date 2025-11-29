defmodule JidoHub.Organizations.Invitation.Checks.CanCreateInvitation do
  @moduledoc """
  Policy check to determine if an actor can create invitations for an organization.

  Allows:
  - Organization owners (via owner_id match)
  - Organization admins (via existing membership with admin role)
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  @impl true
  def describe(_), do: "actor can create invitations for the organization"

  @impl true
  def match?(actor, %{changeset: changeset}, _opts) do
    with %{id: actor_id} <- actor,
         organization_id when not is_nil(organization_id) <-
           Ash.Changeset.get_argument(changeset, :organization_id) do
      check_permissions(actor_id, organization_id)
    else
      _ -> false
    end
  end

  def match?(_actor, _context, _opts), do: false

  defp check_permissions(actor_id, organization_id) do
    case Ash.get(JidoHub.Organizations.Organization, organization_id,
           domain: JidoHub.Organizations,
           authorize?: false
         ) do
      {:ok, %{owner_id: ^actor_id}} ->
        true

      {:ok, _org} ->
        check_admin_membership(actor_id, organization_id)

      _ ->
        false
    end
  end

  defp check_admin_membership(actor_id, organization_id) do
    case JidoHub.Organizations.Membership
         |> Ash.Query.filter(
           user_id == ^actor_id and organization_id == ^organization_id and role == :admin
         )
         |> Ash.read_one(domain: JidoHub.Organizations, authorize?: false) do
      {:ok, %JidoHub.Organizations.Membership{}} -> true
      _ -> false
    end
  end
end
