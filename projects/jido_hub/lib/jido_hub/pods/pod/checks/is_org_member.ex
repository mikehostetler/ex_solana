defmodule JidoHub.Pods.Pod.Checks.IsOrgMember do
  @moduledoc """
  Policy check that verifies the actor is a member of the organization that owns the pod.
  Works for list queries by emitting a DB-level filter.
  """
  use Ash.Policy.FilterCheck

  @impl true
  def describe(_), do: "actor is member of organization that owns pod"

  @impl true
  def filter(nil, _context, _opts), do: false

  def filter(_actor, _context, _opts) do
    import Ash.Expr

    expr(
      owner_type == :organization and
        exists(organization_memberships, user_id == ^actor(:id))
    )
  end
end
