defmodule JidoHub.Organizations.Invitation.Validations.PreventDuplicatePendingInvitation do
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    email = Ash.Changeset.get_attribute(changeset, :email)
    organization_id = Ash.Changeset.get_attribute(changeset, :organization_id)

    if email && organization_id do
      existing =
        JidoHub.Organizations.Invitation
        |> Ash.Query.filter(
          email == ^email and
            organization_id == ^organization_id and
            is_nil(accepted_at) and
            expires_at > ^DateTime.utc_now()
        )
        |> Ash.read_one(domain: JidoHub.Organizations, authorize?: false)

      case existing do
        {:ok, nil} ->
          :ok

        {:ok, _invitation} ->
          {:error,
           field: :email, message: "already has a pending invitation for this organization"}

        {:error, error} ->
          {:error, error}
      end
    else
      :ok
    end
  end
end
