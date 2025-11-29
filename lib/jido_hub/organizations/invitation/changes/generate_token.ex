defmodule JidoHub.Organizations.Invitation.Changes.GenerateToken do
  @moduledoc """
  Generates a secure random token for invitation links.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    token = generate_secure_token()
    Ash.Changeset.change_attribute(changeset, :token, token)
  end

  defp generate_secure_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
    |> String.slice(0, 32)
  end
end
