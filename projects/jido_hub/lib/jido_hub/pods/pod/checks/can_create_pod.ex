defmodule JidoHub.Pods.Pod.Checks.CanCreatePod do
  @moduledoc """
  Checks if the actor can create a pod for a user or organization.
  """

  use Ash.Policy.SimpleCheck

  require Ash.Query

  def describe(_opts), do: "User can create pod for themselves or organizations they admin"

  def match?(nil, _context, _opts), do: false

  def match?(actor, %{changeset: changeset}, _opts) do
    owner_type = Ash.Changeset.get_argument(changeset, :owner_type)
    owner_id = Ash.Changeset.get_argument(changeset, :owner_id)

    case owner_type do
      :user ->
        # User can create pod for themselves
        owner_id == actor.id

      :organization ->
        # Check if user is the direct owner of the organization
        case Ash.get(JidoHub.Organizations.Organization, owner_id,
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
                  organization_id == ^owner_id and
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

      _ ->
        false
    end
  end

  def match?(_, _, _), do: false
end
