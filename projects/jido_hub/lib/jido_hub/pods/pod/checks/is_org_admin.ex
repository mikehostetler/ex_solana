defmodule JidoHub.Pods.Pod.Checks.IsOrgAdmin do
  @moduledoc """
  Checks if the actor is an admin of the organization that owns the pod.
  """

  use Ash.Policy.SimpleCheck

  require Ash.Query

  def describe(_opts), do: "User is admin or owner of the pod's organization"

  def match?(actor, %{changeset: %{data: pod}}, _opts) when pod.owner_type == :organization do
    # For update/destroy actions with a changeset
    check_org_admin(actor, pod.owner_id)
  end

  def match?(actor, %{resource: pod}, _opts) when pod.owner_type == :organization do
    # For read actions
    check_org_admin(actor, pod.owner_id)
  end

  def match?(_, _, _), do: false

  defp check_org_admin(actor, org_id) when not is_nil(actor) do
    # Check if user is the direct owner of the organization
    case Ash.get(JidoHub.Organizations.Organization, org_id,
           domain: JidoHub.Organizations,
           authorize?: false
         ) do
      {:ok, org} ->
        if org.owner_id == actor.id do
          true
        else
          # Otherwise check if they are admin/owner via membership
          query =
            JidoHub.Organizations.Membership
            |> Ash.Query.filter(
              organization_id == ^org_id and
                user_id == ^actor.id and
                role in [:owner, :admin]
            )
            |> Ash.Query.limit(1)

          case Ash.read(query, domain: JidoHub.Organizations, authorize?: false) do
            {:ok, [_]} -> true
            _ -> false
          end
        end

      _ ->
        false
    end
  end

  defp check_org_admin(_, _), do: false
end
