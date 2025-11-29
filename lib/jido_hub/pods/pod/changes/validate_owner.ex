defmodule JidoHub.Pods.Pod.Changes.ValidateOwner do
  @moduledoc """
  Validates that the owner (user or organization) exists.
  """

  use Ash.Resource.Change

  require Ash.Query

  def init(opts), do: {:ok, opts}

  def change(changeset, _opts, _context) do
    owner_type = Ash.Changeset.get_attribute(changeset, :owner_type)
    owner_id = Ash.Changeset.get_attribute(changeset, :owner_id)

    if owner_type && owner_id do
      validate_owner_exists(changeset, owner_type, owner_id)
    else
      changeset
    end
  end

  defp validate_owner_exists(changeset, :user, owner_id) do
    case Ash.get(JidoHub.Accounts.User, owner_id, domain: JidoHub.Accounts, authorize?: false) do
      {:ok, _user} ->
        changeset

      {:error, _} ->
        Ash.Changeset.add_error(changeset,
          field: :owner_id,
          message: "User not found"
        )
    end
  end

  defp validate_owner_exists(changeset, :organization, owner_id) do
    case Ash.get(JidoHub.Organizations.Organization, owner_id,
           domain: JidoHub.Organizations,
           authorize?: false
         ) do
      {:ok, _org} ->
        changeset

      {:error, _} ->
        Ash.Changeset.add_error(changeset,
          field: :owner_id,
          message: "Organization not found"
        )
    end
  end
end
