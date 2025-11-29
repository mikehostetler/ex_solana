defmodule JidoHub.Accounts.User.Changes.NormalizeUsername do
  @moduledoc """
  Normalizes usernames to lowercase and validates format.
  """

  use Ash.Resource.Change

  @reserved_words ~w[
    admin api app auth login logout signup register
    about help support contact privacy terms legal
    blog docs documentation guide tutorial
    dashboard settings profile account users
    organization organizations org orgs
    pod pods workspace workspaces
    jido agent ai llm ml assistant bot chatbot
    gpt claude anthropic openai gemini bard
    system root administrator moderator mod
    public private shared assets static
    css js javascript images img uploads
    download downloads file files
    search query find discover explore
    new create edit update delete remove
    join invite invitation member team
    billing payment subscribe subscription
    webhook webhooks callback callbacks
    test testing debug staging production
    www mail email smtp ftp sftp ssh
    localhost null undefined nil none
    true false yes no
  ]

  def init(opts), do: {:ok, opts}

  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :username) do
      nil ->
        # Try to get from attributes if not in arguments
        case Ash.Changeset.get_attribute(changeset, :username) do
          nil -> changeset
          username -> validate_and_normalize(changeset, username)
        end

      username ->
        validate_and_normalize(changeset, username)
    end
  end

  defp validate_and_normalize(changeset, username) do
    normalized = String.downcase(username)

    cond do
      # Check length
      String.length(normalized) < 4 ->
        Ash.Changeset.add_error(changeset,
          field: :username,
          message: "Username must be at least 4 characters long"
        )

      String.length(normalized) > 30 ->
        Ash.Changeset.add_error(changeset,
          field: :username,
          message: "Username must be at most 30 characters long"
        )

      # Check format (GitHub rules)
      !Regex.match?(~r/^[a-z0-9][a-z0-9_-]*[a-z0-9]$/, normalized) &&
          String.length(normalized) > 1 ->
        Ash.Changeset.add_error(changeset,
          field: :username,
          message:
            "Username must start and end with a letter or number, and can only contain letters, numbers, hyphens, and underscores"
        )

      # Single character usernames must be alphanumeric
      String.length(normalized) == 1 && !Regex.match?(~r/^[a-z0-9]$/, normalized) ->
        Ash.Changeset.add_error(changeset,
          field: :username,
          message: "Single character usernames must be a letter or number"
        )

      # Check reserved words
      normalized in @reserved_words ->
        Ash.Changeset.add_error(changeset,
          field: :username,
          message: "Username '#{normalized}' is reserved and cannot be used"
        )

      # Check for consecutive special characters
      String.contains?(normalized, "__") || String.contains?(normalized, "--") ||
        String.contains?(normalized, "-_") || String.contains?(normalized, "_-") ->
        Ash.Changeset.add_error(changeset,
          field: :username,
          message: "Username cannot contain consecutive special characters"
        )

      true ->
        # Valid username, set the normalized version
        Ash.Changeset.change_attribute(changeset, :username, normalized)
    end
  end
end
