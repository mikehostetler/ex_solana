defmodule Karo.Resources.Message do
  @moduledoc """
  A message within a conversation, representing user, assistant, system, or tool messages.
  """

  use Ash.Resource,
    otp_app: :karo,
    domain: Karo.ChatDomain,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "messages"
    repo Karo.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:conversation_id, :role, :content, :discord_user_id, :metadata]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:user, :assistant, :system, :tool]
    end

    attribute :content, :string do
      allow_nil? false
      public? true
    end

    attribute :discord_user_id, :string do
      allow_nil? true
      public? true
    end

    attribute :metadata, :map do
      allow_nil? false
      public? true
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :conversation, Karo.Resources.Conversation do
      allow_nil? false
      public? true
    end
  end
end
