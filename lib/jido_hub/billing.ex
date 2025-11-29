defmodule JidoHub.Billing do
  @moduledoc """
  Billing context placeholder for JidoHub.

  This module is a stub that provides mock subscription data for development.
  In production, this should be replaced with actual billing integration
  (e.g., Stripe, Paddle, etc.).
  """

  @doc """
  Returns a list of mock subscriptions for development.

  Each subscription has:
  - id: unique identifier
  - status: subscription status (:active, :past_due, :canceled, etc.)
  - plan_id: the plan identifier
  - inserted_at: when the subscription was created
  """
  def list_subscriptions do
    now = DateTime.utc_now()

    [
      %{
        id: Ash.UUID.generate(),
        status: :active,
        plan_id: "pro_monthly",
        inserted_at: DateTime.add(now, -30, :day)
      },
      %{
        id: Ash.UUID.generate(),
        status: :active,
        plan_id: "enterprise_yearly",
        inserted_at: DateTime.add(now, -60, :day)
      },
      %{
        id: Ash.UUID.generate(),
        status: :past_due,
        plan_id: "pro_monthly",
        inserted_at: DateTime.add(now, -15, :day)
      }
    ]
  end

  @doc """
  Returns an Ash-compatible query for subscriptions.

  This is a placeholder that returns the list directly.
  When implementing real billing, this should return an Ash.Query.
  """
  def list_subscriptions_query do
    list_subscriptions()
  end
end
