defmodule JidoHub.Organizations.Membership.Checks.ActorIsAdminOrOwner do
  use Ash.Policy.SimpleCheck

  import Ecto.Query

  @impl true
  def describe(_opts), do: "actor is an admin or owner in the organization"

  @impl true
  def match?(actor, %{data: membership}, _opts)
      when not is_nil(actor) and not is_nil(membership) do
    organization_id = membership.organization_id

    if organization_id do
      # Use Ecto query directly to check if actor is admin/owner in the organization
      result =
        from(m in "memberships",
          where: m.user_id == type(^actor.id, :binary_id),
          where: m.organization_id == type(^organization_id, :binary_id),
          where: m.role in ["admin", "owner"],
          select: count(m.id)
        )
        |> JidoHub.Repo.one()

      result > 0
    else
      false
    end
  end

  def match?(_actor, _context, _opts), do: false
end
