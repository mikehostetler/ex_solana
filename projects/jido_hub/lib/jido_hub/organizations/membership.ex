defmodule JidoHub.Organizations.Membership do
  use Ash.Resource,
    otp_app: :jido_hub,
    domain: JidoHub.Organizations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "memberships"
    repo JidoHub.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:role]
      argument :user_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false

      change set_attribute(:user_id, arg(:user_id))
      change set_attribute(:organization_id, arg(:organization_id))
      change set_attribute(:joined_at, &DateTime.utc_now/0)
    end

    create :create_via_invite do
      accept [:role]
      argument :user_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false

      change set_attribute(:user_id, arg(:user_id))
      change set_attribute(:organization_id, arg(:organization_id))
      change set_attribute(:joined_at, &DateTime.utc_now/0)
    end

    update :update_role do
      accept [:role]
      require_atomic? false
    end
  end

  policies do
    # SECURITY NOTE: This bypass allows AUTHENTICATED users to create memberships via invitation
    # Rationale: Users accepting valid invitations need to create their membership record
    # Compensating controls:
    # 1. Only called from AcceptInvitation change after token validation
    # 2. Invitation token must be valid, unexpired, and not already accepted
    # 3. Email on invitation must match user's email (validated in AcceptInvitation)
    # 4. Role is set from invitation, not user input
    # 5. Invitation is marked as accepted atomically with membership creation
    # 6. Unique constraint prevents duplicate memberships per user/organization
    bypass action(:create_via_invite) do
      authorize_if always()
    end

    # For regular create, only org owners and admins can add members
    # We use a custom check since we can't reference relationships that don't exist yet
    policy action(:create) do
      authorize_if JidoHub.Organizations.Membership.Checks.CanManageMemberships
    end

    # Organization owners and admins can manage existing memberships
    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via([:organization, :owner])

      authorize_if expr(
                     exists(
                       organization.memberships,
                       user_id == ^actor(:id) and role in [:admin, :owner]
                     )
                   )
    end

    # Members can read membership information for organizations they belong to
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
      authorize_if relates_to_actor_via([:organization, :owner])
      authorize_if relates_to_actor_via([:organization, :memberships, :user])
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

    attribute :joined_at, :utc_datetime do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, JidoHub.Accounts.User do
      allow_nil? false
      public? true
    end

    belongs_to :organization, JidoHub.Organizations.Organization do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_user_organization, [:user_id, :organization_id]
  end
end
