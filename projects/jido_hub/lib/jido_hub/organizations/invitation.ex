defmodule JidoHub.Organizations.Invitation do
  use Ash.Resource,
    otp_app: :jido_hub,
    domain: JidoHub.Organizations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "invitations"
    repo JidoHub.Repo

    skip_unique_indexes [:unique_pending_invitation]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:email, :role]
      argument :organization_id, :uuid, allow_nil?: false
      argument :invited_by_id, :uuid, allow_nil?: false

      change set_attribute(:organization_id, arg(:organization_id))
      change set_attribute(:invited_by_id, arg(:invited_by_id))
      change {JidoHub.Organizations.Invitation.Changes.ValidateInvitationPermissions, []}
      change {JidoHub.Organizations.Invitation.Changes.GenerateToken, []}
      change {JidoHub.Organizations.Invitation.Changes.SetExpiration, []}

      validate {JidoHub.Organizations.Invitation.Validations.PreventDuplicatePendingInvitation,
                []}
    end

    update :accept do
      accept []
      require_atomic? false
      argument :token, :string, allow_nil?: false
      argument :accepting_user_id, :uuid, allow_nil?: false

      change {JidoHub.Organizations.Invitation.Changes.AcceptInvitation, []}
    end

    update :resend do
      accept []
      require_atomic? false
      change {JidoHub.Organizations.Invitation.Changes.GenerateToken, []}
      change {JidoHub.Organizations.Invitation.Changes.SetExpiration, []}
    end

    destroy :destroy

    read :by_token do
      get? true
      argument :token, :string, allow_nil?: false

      filter expr(
               token == ^arg(:token) and is_nil(accepted_at) and expires_at > ^DateTime.utc_now()
             )
    end
  end

  policies do
    # SECURITY NOTE: This bypass allows UNAUTHENTICATED users to accept invitations
    # Rationale: Users accepting invitations may not yet have accounts
    # Compensating controls:
    # 1. Token validation - unique, cryptographically secure token required
    # 2. Single-use check - accepted_at must be nil (invitation not already accepted)
    # 3. Expiration check - expires_at must be in the future
    # 4. Email verification - token ties action to specific invited email
    # 5. AcceptInvitation change validates token and creates membership atomically
    bypass action(:accept) do
      authorize_if always()
    end

    # SECURITY NOTE: This bypass allows UNAUTHENTICATED users to lookup invitations by token
    # Rationale: Users need to view invitation details before accepting
    # Compensating controls:
    # 1. Token validation - unique, cryptographically secure token required
    # 2. Filter enforces invitation is pending (accepted_at is nil)
    # 3. Filter enforces invitation is not expired (expires_at > now)
    # 4. Read-only action - no mutations possible
    # 5. Token is sensitive and not exposed in responses
    bypass action(:by_token) do
      authorize_if always()
    end

    # For create actions, verify actor is owner or admin of the organization
    policy action_type(:create) do
      authorize_if JidoHub.Organizations.Invitation.Checks.CanCreateInvitation
    end

    # For read, update, destroy use relationship-based authorization
    policy action_type([:read, :update, :destroy]) do
      authorize_if relates_to_actor_via([:organization, :owner])

      authorize_if expr(
                     organization.memberships.user_id == ^actor(:id) and
                       organization.memberships.role in [:admin, :owner]
                   )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true

      constraints max_length: 255,
                  match: ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/
    end

    attribute :role, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:admin, :member]
      default :member
    end

    attribute :token, :string do
      allow_nil? false
      public? true
      sensitive? true
    end

    attribute :expires_at, :utc_datetime do
      allow_nil? false
      public? true
    end

    attribute :accepted_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, JidoHub.Organizations.Organization do
      allow_nil? false
      public? true
    end

    belongs_to :invited_by, JidoHub.Accounts.User do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_token, [:token]

    identity :unique_pending_invitation, [:email, :organization_id] do
      where expr(is_nil(accepted_at) and expires_at > ^DateTime.utc_now())
    end
  end
end
