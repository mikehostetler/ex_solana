defmodule JidoHub.Organizations.Invitation.Changes.AcceptInvitation do
  @moduledoc """
  Handles the acceptance of an invitation by creating a membership and marking the invitation as accepted.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    with {:ok, token} <- get_token_from_args(changeset),
         {:ok, accepting_user_id} <- get_accepting_user_id_from_args(changeset),
         {:ok, invitation} <- get_invitation_by_token(changeset, token),
         :ok <- validate_invitation(invitation),
         :ok <- validate_email_match(changeset, invitation, accepting_user_id),
         :ok <- validate_not_already_member(changeset, invitation, accepting_user_id) do
      # Mark invitation as accepted
      changeset = Ash.Changeset.change_attribute(changeset, :accepted_at, DateTime.utc_now())

      # Create membership in after_action hook
      Ash.Changeset.after_action(changeset, fn changeset, invitation ->
        create_membership(changeset, invitation, accepting_user_id, context)
        {:ok, invitation}
      end)
    else
      {:error, reason} ->
        Ash.Changeset.add_error(changeset, reason)
    end
  end

  defp get_token_from_args(changeset) do
    case Ash.Changeset.get_argument(changeset, :token) do
      nil -> {:error, "Token is required"}
      token -> {:ok, token}
    end
  end

  defp get_accepting_user_id_from_args(changeset) do
    case Ash.Changeset.get_argument(changeset, :accepting_user_id) do
      nil -> {:error, "Accepting user ID is required"}
      user_id -> {:ok, user_id}
    end
  end

  defp get_invitation_by_token(changeset, token) do
    domain = changeset.domain

    case Ash.get(JidoHub.Organizations.Invitation, changeset.data.id,
           domain: domain,
           authorize?: false
         ) do
      {:ok, invitation} ->
        if invitation.token == token do
          {:ok, invitation}
        else
          {:error, "Invalid token"}
        end

      {:error, _} ->
        {:error, "Invitation not found"}
    end
  end

  defp validate_invitation(invitation) do
    cond do
      not is_nil(invitation.accepted_at) ->
        {:error, "Invitation has already been accepted"}

      DateTime.before?(invitation.expires_at, DateTime.utc_now()) ->
        {:error, "Invitation has expired"}

      true ->
        :ok
    end
  end

  defp validate_email_match(_changeset, invitation, accepting_user_id) do
    case Ash.get(JidoHub.Accounts.User, accepting_user_id,
           domain: JidoHub.Accounts,
           authorize?: false
         ) do
      {:ok, user} ->
        if user.email == invitation.email do
          :ok
        else
          {:error, "Email does not match invitation"}
        end

      {:error, _} ->
        {:error, "User not found"}
    end
  end

  defp validate_not_already_member(changeset, invitation, accepting_user_id) do
    domain = changeset.domain

    case JidoHub.Organizations.Membership
         |> Ash.Query.filter(
           user_id == ^accepting_user_id and
             organization_id == ^invitation.organization_id
         )
         |> Ash.read_one(domain: domain, authorize?: false) do
      {:ok, nil} -> :ok
      {:ok, _membership} -> {:error, "User is already a member of this organization"}
      {:error, _} -> {:error, "Failed to check membership status"}
    end
  end

  defp create_membership(changeset, invitation, accepting_user_id, _context) do
    domain = changeset.domain

    JidoHub.Organizations.Membership
    |> Ash.Changeset.new()
    |> Ash.Changeset.set_argument(:user_id, accepting_user_id)
    |> Ash.Changeset.set_argument(:organization_id, invitation.organization_id)
    |> Ash.Changeset.for_create(:create_via_invite, %{role: invitation.role})
    |> Ash.create(domain: domain, authorize?: false)
  end
end
