defmodule JidoHub.Organizations.Invitation.Changes.SetExpiration do
  @moduledoc """
  Sets the expiration date for invitations (default 7 days from now).
  """
  use Ash.Resource.Change

  @default_expiration_days 7

  @impl true
  def change(changeset, opts, _context) do
    days = Keyword.get(opts, :days, @default_expiration_days)
    expires_at = DateTime.utc_now() |> DateTime.add(days * 24 * 60 * 60, :second)
    Ash.Changeset.change_attribute(changeset, :expires_at, expires_at)
  end
end
