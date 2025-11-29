defmodule JidoHub.Logs.Log do
  use Ash.Resource,
    otp_app: :jido_hub,
    domain: JidoHub.Logs,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  postgres do
    table "logs"
    repo JidoHub.Repo
  end

  code_interface do
    define :create, action: :create
    define :by_filters, action: :by_filters
    define :read, action: :read
  end

  actions do
    defaults [:read]

    create :create do
      accept [:action, :user_type, :metadata, :user_id, :target_user_id, :org_id]

      change after_action(fn _changeset, log, _context ->
               JidoHubWeb.Endpoint.broadcast("logs", "new-log", log)
               {:ok, log}
             end)
    end

    read :by_filters do
      argument :action, :string, allow_nil?: true
      argument :user_id, :uuid, allow_nil?: true
      argument :org_id, :uuid, allow_nil?: true

      prepare fn query, _context ->
        query
        |> filter_by_action()
        |> filter_by_user_id()
        |> filter_by_org_id()
        |> Ash.Query.sort(inserted_at: :desc)
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(^actor(:role) == :admin)
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type([:update, :destroy]) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :action, :string do
      allow_nil? false
      public? true
    end

    attribute :user_type, :string do
      allow_nil? false
      public? true
      default "user"
    end

    attribute :metadata, :map do
      allow_nil? false
      public? true
      default %{}
    end

    attribute :user_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :target_user_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :org_id, :uuid do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, JidoHub.Accounts.User do
      define_attribute? false
      allow_nil? true
      public? true
    end

    belongs_to :target_user, JidoHub.Accounts.User do
      define_attribute? false
      allow_nil? true
      public? true
    end

    belongs_to :organization, JidoHub.Organizations.Organization do
      define_attribute? false
      allow_nil? true
      public? true
      attribute_writable? false
      source_attribute :org_id
    end
  end

  defp filter_by_action(query) do
    case Ash.Query.get_argument(query, :action) do
      nil -> query
      action_value -> Ash.Query.filter(query, action == ^action_value)
    end
  end

  defp filter_by_user_id(query) do
    case Ash.Query.get_argument(query, :user_id) do
      nil ->
        query

      user_id_value ->
        Ash.Query.filter(query, user_id == ^user_id_value or target_user_id == ^user_id_value)
    end
  end

  defp filter_by_org_id(query) do
    case Ash.Query.get_argument(query, :org_id) do
      nil -> query
      org_id_value -> Ash.Query.filter(query, org_id == ^org_id_value)
    end
  end
end
