defmodule JidoHub.Accounts.User.Validations.ValidateSlug do
  @moduledoc """
  Validates that a username is not a reserved route slug.
  Format validation is handled by NormalizeUsername change.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    # Get the username - it may have been normalized by NormalizeUsername change
    username = Ash.Changeset.get_attribute(changeset, :username)

    # If username is in the changeset arguments (not yet normalized), normalize it for validation
    username =
      if username do
        username
      else
        case Ash.Changeset.fetch_argument(changeset, :username) do
          {:ok, arg_username} when is_binary(arg_username) -> String.downcase(arg_username)
          _ -> nil
        end
      end

    if username && username in JidoHub.Slugs.reserved_slugs() do
      {:error, field: :username, message: "#{username} is a reserved slug"}
    else
      :ok
    end
  end
end
