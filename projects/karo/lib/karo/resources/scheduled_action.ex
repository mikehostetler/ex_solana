defmodule Karo.Resources.ScheduledAction do
  @moduledoc """
  A scheduled action for a conversation, such as reminders, summaries, or check-ins.
  """

  use Ash.Resource,
    otp_app: :karo,
    domain: Karo.ChatDomain,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "scheduled_actions"
    repo Karo.Repo
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:reminder, :summary, :checkin]
    end

    attribute :run_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :payload, :map do
      allow_nil? false
      public? true
      default %{}
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      default :scheduled
      constraints one_of: [:scheduled, :running, :completed, :failed]
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
