defmodule JidoHub.Pods.PodMembership do
  @moduledoc """
  Represents membership in a user-owned pod.
  Organization-owned pods use organization memberships.
  """

  use Ash.Resource,
    otp_app: :jido_hub,
    domain: JidoHub.Pods,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :pod_id, :user_id, :role, :joined_at]
  end

  postgres do
    table "pod_memberships"
    repo JidoHub.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:pod_id, :user_id, :role]

      change set_attribute(:joined_at, &DateTime.utc_now/0)

      # Prevent org-owned pods from having PodMemberships
      change fn changeset, _ctx ->
        pod_id = Ash.Changeset.get_attribute(changeset, :pod_id)

        case Ash.get(JidoHub.Pods.Pod, pod_id, domain: JidoHub.Pods, authorize?: false) do
          {:ok, %{owner_type: :organization}} ->
            Ash.Changeset.add_error(
              changeset,
              field: :pod_id,
              message: "Organization-owned pods use Organization memberships"
            )

          {:ok, %{owner_type: :user}} ->
            changeset

          {:error, _} = error ->
            Ash.Changeset.add_error(changeset, field: :pod_id, message: "Pod not found")

          _ ->
            changeset
        end
      end
    end

    update :update do
      primary? true
      accept [:role]
    end

    destroy :destroy do
      primary? true
    end
  end

  policies do
    # Users can read their own memberships or if they own the pod
    policy action(:read) do
      authorize_if relates_to_actor_via(:user)
      authorize_if expr(pod.owner_type == :user and pod.owner_id == ^actor(:id))
    end

    # Only pod owners can create memberships (uses custom check for creates)
    policy action(:create) do
      authorize_if JidoHub.Pods.PodMembership.Checks.ActorOwnsUserPod
    end

    # Only pod owners can update/destroy memberships (uses expr since data exists)
    policy action([:update, :destroy]) do
      authorize_if expr(pod.owner_type == :user and pod.owner_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:owner, :admin, :member]
      default :member
    end

    attribute :joined_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :pod, JidoHub.Pods.Pod do
      allow_nil? false
      public? true
    end

    belongs_to :user, JidoHub.Accounts.User do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_membership, [:pod_id, :user_id]
  end
end
