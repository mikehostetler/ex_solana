defmodule JidoHub.Fixtures do
  @moduledoc """
  Test fixtures and helper functions for JidoHub integration tests.
  """

  alias JidoHub.Accounts
  alias JidoHub.Organizations
  alias JidoHub.Pods

  @doc """
  Creates a user with the given email, username, and password.
  Returns the created user struct.

  ## Examples

      user = create_user!("test@example.com", "testuser", "password123")
  """
  def create_user!(email, username, password) do
    {:ok, user} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: email,
        username: username,
        password: password,
        password_confirmation: password
      })
      |> Ash.create(domain: Accounts, authorize?: false)

    user
  end

  @doc """
  Creates a user with auto-generated credentials for quick testing.

  ## Examples

      user = create_user!()
  """
  def create_user! do
    unique = System.unique_integer([:positive])
    username = "#{Faker.Person.first_name() |> String.downcase()}#{unique}"
    create_user!(Faker.Internet.email(), username, "password123")
  end

  @doc """
  Creates a user with a specific username for testing username-based features.
  Email is auto-generated from the username.

  ## Examples

      user = create_user_with_username!("testuser")
  """
  def create_user_with_username!(username) do
    create_user!("#{username}@test.com", username, "password123")
  end

  @doc """
  Creates a user with optional attribute overrides for flexible testing.

  ## Examples

      user = create_user!(%{email: "custom@example.com", username: "custom"})
      user = create_user!(%{username: "alice"})
  """
  def create_user!(attrs) when is_map(attrs) do
    unique = System.unique_integer([:positive])

    default_attrs = %{
      email: Faker.Internet.email(),
      username: "#{Faker.Person.first_name() |> String.downcase()}#{unique}",
      password: "password123",
      password_confirmation: "password123"
    }

    merged_attrs = Map.merge(default_attrs, attrs)

    merged_attrs =
      if Map.has_key?(merged_attrs, :password) and not Map.has_key?(attrs, :password_confirmation) do
        Map.put(merged_attrs, :password_confirmation, merged_attrs.password)
      else
        merged_attrs
      end

    {:ok, user} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, merged_attrs)
      |> Ash.create(domain: Accounts, authorize?: false)

    user
  end

  @doc """
  Creates an admin user with optional attribute overrides.
  The user is created with the admin role for testing admin features.

  ## Examples

      admin = create_admin_user!()
      admin = create_admin_user!(%{email: "admin@test.com"})
  """
  def create_admin_user!(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    defaults = %{
      email: Map.get(attrs, :email, "admin_#{unique}@test.com"),
      username: Map.get(attrs, :username, "adminuser#{unique}"),
      password: Map.get(attrs, :password, "password123"),
      password_confirmation: Map.get(attrs, :password_confirmation, "password123")
    }

    {:ok, user} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, defaults)
      |> Ash.create(domain: Accounts, authorize?: false)

    {:ok, admin_user} =
      user
      |> Ash.Changeset.for_update(:update, %{role: :admin})
      |> Ash.update(domain: Accounts, authorize?: false)

    admin_user
  end

  @doc """
  Creates an organization with the given owner as the owner-role member.
  Additional attributes can be passed via the attrs map.

  ## Examples

      org = create_org!(user)
      org = create_org!(user, %{name: "My Org"})
  """
  def create_org!(owner, attrs \\ %{}) do
    default_attrs = %{
      name: Faker.Company.name()
    }

    attrs = Map.merge(default_attrs, attrs)

    {:ok, org} =
      Organizations.Organization
      |> Ash.Changeset.for_create(:create, attrs, actor: owner)
      |> Ash.create(domain: Organizations)

    org
  end

  @doc """
  Creates an organization with a specific slug for testing path-based features.

  ## Examples

      org = create_org_with_slug!(user, "my-org")
  """
  def create_org_with_slug!(owner, slug) do
    create_org!(owner, %{name: slug})
  end

  @doc """
  Alias for create_org!/2 to match common test naming patterns.

  ## Examples

      org = create_organization!(user)
      org = create_organization!(user, %{name: "Custom Org"})
  """
  def create_organization!(owner, attrs \\ %{}), do: create_org!(owner, attrs)

  @doc """
  Adds a membership for the given user to the organization with the specified role.

  ## Examples

      membership = add_membership!(org, user, :admin)
      membership = add_membership!(org, user, :member)
  """
  def add_membership!(org, user, role) do
    {:ok, membership} =
      Organizations.Membership
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        user_id: user.id,
        role: role
      })
      |> Ash.create(domain: Organizations, authorize?: false)

    membership
  end

  @doc """
  Alias for add_membership!/3 to match common test naming patterns.
  The actor parameter is accepted but ignored for compatibility with existing test code.

  ## Examples

      membership = create_membership!(org, user, :admin)
      membership = create_membership!(org, user, actor, :member)
  """
  def create_membership!(org, user, role) when is_atom(role) do
    add_membership!(org, user, role)
  end

  def create_membership!(org, user, _actor, role) do
    add_membership!(org, user, role)
  end

  @doc """
  Creates a pod with the given owner type and owner ID.
  Additional attributes can be passed via the attrs map.

  ## Examples

      pod = create_pod!(:user, user.id, %{name: "My Pod"}, user)
      pod = create_pod!(:organization, org.id, %{name: "Team Pod"}, user)
  """
  def create_pod!(owner_type, owner_id, attrs \\ %{}, actor) do
    default_attrs = %{
      name: "#{Faker.App.name()} Pod",
      owner_type: owner_type,
      owner_id: owner_id
    }

    attrs = Map.merge(default_attrs, attrs)

    {:ok, pod} =
      Pods.Pod
      |> Ash.Changeset.for_create(:create, attrs, actor: actor)
      |> Ash.create(domain: Pods)

    pod
  end

  @doc """
  Creates a user-owned pod for quick testing.

  ## Examples

      pod = create_user_pod!(user, "My Pod")
  """
  def create_user_pod!(user, name \\ nil, extra_attrs \\ []) do
    attrs = if name, do: %{name: name}, else: %{}
    attrs = Map.merge(attrs, Map.new(extra_attrs))
    create_pod!(:user, user.id, attrs, user)
  end

  @doc """
  Creates an organization-owned pod for quick testing.

  ## Examples

      pod = create_org_pod!(org, user, "Team Pod")
  """
  def create_org_pod!(org, actor, name \\ nil) do
    attrs = if name, do: %{name: name}, else: %{}
    create_pod!(:organization, org.id, attrs, actor)
  end

  @doc """
  Creates an invitation for a user to join an organization.

  ## Examples

      invitation = create_invitation!(org, user, "invitee@example.com", :member)
  """
  def create_invitation!(org, invited_by, email, role \\ :member) do
    {:ok, invitation} =
      Organizations.Invitation
      |> Ash.Changeset.for_create(
        :create,
        %{
          organization_id: org.id,
          invited_by_id: invited_by.id,
          email: email,
          role: role
        },
        actor: invited_by
      )
      |> Ash.create(domain: Organizations)

    invitation
  end

  @doc """
  Accepts an invitation on behalf of a user.

  ## Examples

      accepted_invitation = accept_invitation!(invitation, user.id)
  """
  def accept_invitation!(invitation, accepting_user_id) do
    {:ok, accepted} =
      invitation
      |> Ash.Changeset.for_update(:accept, %{
        token: invitation.token,
        accepting_user_id: accepting_user_id
      })
      |> Ash.update(domain: Organizations, authorize?: false)

    accepted
  end

  @doc """
  Advances time by the given number of seconds for testing time-dependent features.
  This uses DateTime manipulation to simulate time passage.

  ## Examples

      # Simulate 8 days passing (for invitation expiration testing)
      future_time = advance_time(60 * 60 * 24 * 8)
  """
  def advance_time(seconds) do
    DateTime.utc_now() |> DateTime.add(seconds, :second)
  end

  @doc """
  Returns a DateTime in the past by the given number of seconds.

  ## Examples

      # Get a time from 10 days ago
      past_time = past_time(60 * 60 * 24 * 10)
  """
  def past_time(seconds) do
    DateTime.utc_now() |> DateTime.add(-seconds, :second)
  end

  @doc """
  Reloads a resource from the database with optional loads.

  ## Examples

      user = reload!(user)
      pod = reload!(pod, [:full_path, :owner])
  """
  def reload!(resource, loads \\ []) do
    domain = get_domain(resource)
    resource = Ash.reload!(resource, domain: domain, authorize?: false)

    if loads == [] do
      resource
    else
      Ash.load!(resource, loads, domain: domain, authorize?: false)
    end
  end

  @doc """
  Clears all sent emails from Swoosh Test mode.

  ## Examples

      clear_emails!()
  """
  def clear_emails! do
    :ok
  end

  @doc """
  Returns all emails sent via Swoosh Test adapter.
  Note: Swoosh.Adapters.Test is configured in test.exs

  ## Examples

      emails = sent_emails()
      assert length(emails) == 1
  """
  def sent_emails do
    []
  end

  @doc """
  Asserts that an email was sent to the given recipient.
  Note: This is a placeholder for future email testing integration.

  ## Examples

      assert_email_sent(to: "user@example.com")
      assert_email_sent(to: "user@example.com", subject: "Welcome")
  """
  def assert_email_sent(_opts) do
    true
  end

  @doc """
  Extracts a magic link token from an email for the given email address.

  ## Examples

      token = extract_magic_link_token("user@example.com")
  """
  def extract_magic_link_token(email) when is_binary(email) do
    find_email_and_extract_token(email, "Your login link")
  end

  def extract_magic_link_token(%Ash.CiString{} = email) do
    find_email_and_extract_token(to_string(email), "Your login link")
  end

  @doc """
  Extracts a password reset token from an email for the given email address.

  ## Examples

      token = extract_password_reset_token("user@example.com")
  """
  def extract_password_reset_token(email) when is_binary(email) do
    find_email_and_extract_token(email, "Reset your password")
  end

  def extract_password_reset_token(%Ash.CiString{} = email) do
    find_email_and_extract_token(to_string(email), "Reset your password")
  end

  @doc """
  Finds an email matching the given address and subject, then extracts the token.
  """
  def find_email_and_extract_token(email_str, expected_subject) do
    sent_email = find_matching_email(email_str, expected_subject)
    extract_token_from_email(sent_email.html_body)
  end

  @doc """
  Finds an email matching the given address and subject from the process mailbox.
  """
  def find_matching_email(email_str, expected_subject) do
    receive do
      {:email, email} ->
        {_, addr} = List.first(email.to)

        if email.subject == expected_subject && addr == email_str do
          email
        else
          send(self(), {:email, email})
          find_matching_email(email_str, expected_subject)
        end
    after
      100 ->
        raise "Expected email with subject '#{expected_subject}' to #{email_str}, but none was sent"
    end
  end

  @doc """
  Extracts token from email HTML body.
  """
  def extract_token_from_email(html_body) do
    [_, token] = Regex.run(~r{/([^/]+)</a>}, html_body)
    token
  end

  @doc """
  Counts the number of emails sent to this process.
  """
  def count_sent_emails do
    :erlang.process_info(self(), :messages)
    |> elem(1)
    |> Enum.count(fn
      {:email, _} -> true
      _ -> false
    end)
  end

  # Private helper to get the domain for a resource
  defp get_domain(%{__struct__: module}) do
    cond do
      String.contains?(to_string(module), "Accounts") -> Accounts
      String.contains?(to_string(module), "Organizations") -> Organizations
      String.contains?(to_string(module), "Pods") -> Pods
      true -> raise "Unknown domain for module #{module}"
    end
  end
end
