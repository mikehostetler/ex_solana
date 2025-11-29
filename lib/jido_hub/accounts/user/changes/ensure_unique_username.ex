defmodule JidoHub.Accounts.User.Changes.EnsureUniqueUsername do
  @moduledoc """
  Ensures username is unique across all users.
  """

  use Ash.Resource.Change

  def init(opts), do: {:ok, opts}

  def change(changeset, _opts, _context) do
    username = Ash.Changeset.get_attribute(changeset, :username)
    current_id = Ash.Changeset.get_attribute(changeset, :id)

    if username && username_exists?(changeset.domain, username, current_id) do
      Ash.Changeset.add_error(changeset,
        field: :username,
        message: "Username '#{username}' is already taken"
      )
    else
      changeset
    end
  end

  defp username_exists?(domain, username, current_id) do
    query = JidoHub.Accounts.User

    # Exclude current user if updating
    query =
      if current_id do
        Ash.Query.filter(query, id != ^current_id)
      else
        query
      end

    query
    |> Ash.Query.filter(username == ^username)
    |> Ash.Query.limit(1)
    |> Ash.read!(domain: domain, authorize?: false)
    |> case do
      [] -> false
      _ -> true
    end
  end
end
