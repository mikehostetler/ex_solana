defmodule JidoHub.Pods.Pod do
  @moduledoc """
  A Pod is a workspace that can be owned by either a user or an organization.
  """

  use Ash.Resource,
    otp_app: :jido_hub,
    domain: JidoHub.Pods,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :name, :slug, :owner_type, :inserted_at]
  end

  postgres do
    table "pods"
    repo JidoHub.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:visibility]

      argument :name, :string do
        allow_nil? false
      end

      argument :description, :string do
        allow_nil? true
      end

      argument :owner_type, :atom do
        allow_nil? false
        constraints one_of: [:user, :organization]
      end

      argument :owner_id, :uuid do
        allow_nil? false
      end

      change set_attribute(:name, arg(:name))
      change set_attribute(:description, arg(:description))
      change set_attribute(:owner_type, arg(:owner_type))
      change set_attribute(:owner_id, arg(:owner_id))
      change JidoHub.Pods.Pod.Changes.GenerateSlug
      change JidoHub.Pods.Pod.Changes.ValidateOwner
    end

    update :update do
      primary? true
      accept [:name, :description, :settings]
      require_atomic? false

      change JidoHub.Pods.Pod.Changes.GenerateSlug
    end

    destroy :destroy do
      primary? true
    end

    read :by_slug do
      description "Get a pod by owner and slug"

      argument :owner_type, :atom do
        allow_nil? false
        constraints one_of: [:user, :organization]
      end

      argument :owner_id, :uuid do
        allow_nil? false
      end

      argument :slug, :string do
        allow_nil? false
      end

      filter expr(
               owner_type == ^arg(:owner_type) and
                 owner_id == ^arg(:owner_id) and
                 slug == ^arg(:slug)
             )
    end

    read :for_owner do
      description "List all pods for a specific owner"

      argument :owner_type, :atom do
        allow_nil? false
        constraints one_of: [:user, :organization]
      end

      argument :owner_id, :uuid do
        allow_nil? false
      end

      filter expr(owner_type == ^arg(:owner_type) and owner_id == ^arg(:owner_id))
    end
  end

  policies do
    # Create - Users can create personal pods, org admins can create org pods
    policy action(:create) do
      authorize_if JidoHub.Pods.Pod.Checks.CanCreatePod
    end

    # Read - Public pods are world-readable, private pods require ownership/membership
    policy action_type(:read) do
      # Rule 1: Allow read if the pod is explicitly marked as public
      authorize_if expr(visibility == :public)

      # Rule 2: Personal pods - owner can read their own private pods
      authorize_if expr(owner_type == :user and owner_id == ^actor(:id))

      # Rule 3: Organization pods - org members can read private org pods
      authorize_if JidoHub.Pods.Pod.Checks.IsOrgMember

      # Rule 4: Pod memberships - members can read (for user-owned pods)
      authorize_if expr(exists(pod_memberships, user_id == ^actor(:id)))
    end

    # Update/Delete - Owner or org admin only
    policy action_type([:update, :destroy]) do
      authorize_if expr(owner_type == :user and owner_id == ^actor(:id))
      authorize_if JidoHub.Pods.Pod.Checks.IsOrgAdmin
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
      constraints match: ~r/^[a-z0-9\-]+$/
    end

    attribute :description, :string do
      public? true
    end

    attribute :owner_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:user, :organization]
    end

    attribute :owner_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :settings, :map do
      public? true
      default %{}
    end

    attribute :metadata, :map do
      public? true
      default %{}
    end

    attribute :visibility, :atom do
      allow_nil? false
      public? true
      default :private
      constraints one_of: [:public, :private]
    end

    timestamps()
  end

  relationships do
    has_many :pod_memberships, JidoHub.Pods.PodMembership do
      destination_attribute :pod_id
      filter expr(pod.owner_type == :user)
    end

    has_many :organization_memberships, JidoHub.Organizations.Membership do
      no_attributes? true
      filter expr(organization_id == parent(owner_id))
    end
  end

  calculations do
    calculate :full_path, :string, JidoHub.Pods.Pod.Calculations.FullPath
    calculate :owner, :map, JidoHub.Pods.Pod.Calculations.Owner
  end

  identities do
    identity :unique_slug_per_owner, [:owner_type, :owner_id, :slug]
  end
end
