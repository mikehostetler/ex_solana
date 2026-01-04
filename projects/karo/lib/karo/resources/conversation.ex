defmodule Karo.Resources.Conversation do
  @moduledoc """
  A conversation represents a chat session, typically tied to a Discord channel or thread.
  """

  use Ash.Resource,
    otp_app: :karo,
    domain: Karo.ChatDomain,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "conversations"
    repo Karo.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :discord_guild_id,
        :discord_channel_id,
        :discord_thread_id,
        :title,
        :status,
        :last_activity_at
      ]
    end

    update :update do
      accept [:title, :status, :last_activity_at]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :discord_guild_id, :string do
      allow_nil? true
      public? true
    end

    attribute :discord_channel_id, :string do
      allow_nil? false
      public? true
    end

    attribute :discord_thread_id, :string do
      allow_nil? true
      public? true
    end

    attribute :title, :string do
      allow_nil? true
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      default :open
      constraints one_of: [:open, :closed, :archived]
    end

    attribute :last_activity_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :messages, Karo.Resources.Message do
      destination_attribute :conversation_id
    end

    has_many :scheduled_actions, Karo.Resources.ScheduledAction do
      destination_attribute :conversation_id
    end
  end

  identities do
    identity :discord_key, [:discord_guild_id, :discord_channel_id, :discord_thread_id]
  end
end
