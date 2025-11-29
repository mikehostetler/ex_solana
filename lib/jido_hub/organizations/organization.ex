defmodule JidoHub.Organizations.Organization do
  use Ash.Resource,
    otp_app: :jido_hub,
    domain: JidoHub.Organizations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "organizations"
    repo JidoHub.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :description, :settings]

      change relate_actor(:owner)
      change {JidoHub.Organizations.Organization.Changes.GenerateSlug, []}
      validate JidoHub.Organizations.Organization.Validations.ValidateSlug
    end

    update :update do
      accept [:name, :description, :settings]
      require_atomic? false
      change {JidoHub.Organizations.Organization.Changes.GenerateSlug, []}
      validate JidoHub.Organizations.Organization.Validations.ValidateSlug
    end

    update :transfer_ownership do
      accept []
      argument :new_owner_id, :uuid, allow_nil?: false
      change set_attribute(:owner_id, arg(:new_owner_id))
    end

    # Admin actions
    read :admin_index do
      pagination offset?: true, keyset?: true, required?: false

      prepare fn query, _context ->
        # Admin index should bypass tenant filtering
        query
      end
    end

    create :admin_create do
      accept [:name, :description, :settings]
      argument :owner_id, :uuid, allow_nil?: false
      change set_attribute(:owner_id, arg(:owner_id))
      change {JidoHub.Organizations.Organization.Changes.GenerateSlug, []}
      validate JidoHub.Organizations.Organization.Validations.ValidateSlug
    end

    update :admin_update do
      accept [:name, :description, :settings]
      argument :owner_id, :uuid, allow_nil?: true

      change manage_relationship(:owner_id, :owner, type: :append_and_remove),
        where: [present(:owner_id)]

      require_atomic? false
      change {JidoHub.Organizations.Organization.Changes.GenerateSlug, []}
      validate JidoHub.Organizations.Organization.Validations.ValidateSlug
    end
  end

  policies do
    # Admin actions - only admin users can use these, bypass tenant filtering
    bypass action([:admin_index, :admin_create, :admin_update]) do
      authorize_if expr(^actor(:role) == :admin)
    end

    # Explicitly forbid non-admin users from admin actions with strict checking
    policy action([:admin_index, :admin_create, :admin_update]) do
      access_type :strict
      forbid_if expr(^actor(:role) != :admin)
    end

    # Only authenticated users can read organizations they have access to
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:owner)
      authorize_if relates_to_actor_via([:memberships, :user])
    end

    # Only authenticated users can create organizations - ownership will be set to the actor
    policy action_type(:create) do
      authorize_if actor_present()
    end

    # Only the owner can update or destroy organizations
    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via(:owner)
    end

    # Special policy for transfer_ownership
    policy action(:transfer_ownership) do
      authorize_if relates_to_actor_via(:owner)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 255
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
      constraints match: ~r/^[a-z0-9\-]+$/
    end

    attribute :description, :string do
      public? true
      constraints max_length: 1000
    end

    attribute :settings, :map do
      public? true
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :owner, JidoHub.Accounts.User do
      allow_nil? false
      public? true
      attribute_writable? false
    end

    has_many :memberships, JidoHub.Organizations.Membership do
      public? true
    end

    many_to_many :members, JidoHub.Accounts.User do
      through JidoHub.Organizations.Membership
      join_relationship :memberships
      source_attribute_on_join_resource :organization_id
      destination_attribute_on_join_resource :user_id
      public? true
    end
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
