# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     JidoHub.Repo.insert!(%JidoHub.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

import Ash.Expr

require Ash.Query

# Helper function to get user by email
defmodule SeedHelpers do
  def get_user_by_email(email) do
    case JidoHub.Accounts.User
         |> Ash.Query.for_read(:get_by_email, %{email: email})
         |> Ash.read_one(domain: JidoHub.Accounts, authorize?: false) do
      {:ok, user} -> user
      {:error, _} -> nil
    end
  end

  def ensure_membership(user_id, organization_id, role) do
    # Check if membership already exists
    existing =
      JidoHub.Organizations.Membership
      |> Ash.Query.filter(expr(user_id == ^user_id and organization_id == ^organization_id))
      |> Ash.read_one(domain: JidoHub.Organizations, authorize?: false)

    case existing do
      {:ok, nil} ->
        # Create new membership
        case JidoHub.Organizations.Membership
             |> Ash.Changeset.for_create(:create, %{
               user_id: user_id,
               organization_id: organization_id,
               role: role
             })
             |> Ash.create(domain: JidoHub.Organizations, authorize?: false) do
          {:ok, membership} ->
            {:created, membership}

          {:error, error} ->
            {:error, error}
        end

      {:ok, membership} ->
        # Update role if different
        if membership.role == role do
          {:unchanged, membership}
        else
          case membership
               |> Ash.Changeset.for_update(:update_role, %{role: role})
               |> Ash.update(domain: JidoHub.Organizations, authorize?: false) do
            {:ok, updated_membership} ->
              {:updated, updated_membership}

            {:error, error} ->
              {:error, error}
          end
        end

      {:error, error} ->
        {:error, error}
    end
  end
end

# Create test users with usernames (idempotent)
# Using fixed emails for seed data consistency in dev environment
users_data = [
  %{email: "alice@example.com", username: "alice"},
  %{email: "bob@example.com", username: "bob_smith"},
  %{email: "charlie@example.com", username: "charlie-dev"}
]

# Optionally, you can generate additional random users with Faker:
# users_data = users_data ++ [
#   %{email: Faker.Internet.email(), username: Faker.Internet.user_name()},
#   %{email: Faker.Internet.email(), username: Faker.Internet.user_name()}
# ]

for user_data <- users_data do
  # Check if user already exists by email
  existing =
    JidoHub.Accounts.User
    |> Ash.Query.for_read(:get_by_email, %{email: user_data.email})
    |> Ash.read_one(domain: JidoHub.Accounts, authorize?: false)

  case existing do
    {:ok, nil} ->
      # User doesn't exist, create it
      {:ok, user} =
        JidoHub.Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: user_data.email,
          username: user_data.username,
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: JidoHub.Accounts, authorize?: false)

      IO.puts("Created user: #{user.email} with username: #{user.username}")

    {:ok, user} ->
      # User already exists
      IO.puts("User already exists: #{user.email} with username: #{user.username}")

    {:error, _} ->
      IO.puts("Error checking for user: #{user_data.email}")
  end
end

# Create organizations (idempotent)
IO.puts("\n=== Setting up Organizations ===")

alice = SeedHelpers.get_user_by_email("alice@example.com")
bob = SeedHelpers.get_user_by_email("bob@example.com")
charlie = SeedHelpers.get_user_by_email("charlie@example.com")

organizations_data = [
  %{
    name: "AgentJido",
    description: "Default organization for local development",
    owner: alice,
    members: [{bob, :member}, {charlie, :member}]
  },
  %{
    name: "Tech Innovators",
    description: "Building the future of AI-powered automation",
    owner: bob,
    members: [{alice, :admin}]
  },
  %{
    name: "Data Science Labs",
    description: "Research and development in machine learning",
    owner: charlie,
    members: [{alice, :member}, {bob, :member}]
  },
  %{
    name: "Cloud Solutions Inc",
    description: "Enterprise cloud infrastructure and services",
    owner: alice,
    members: []
  },
  %{
    name: "DevOps Masters",
    description: "Streamlining software delivery pipelines",
    owner: bob,
    members: [{charlie, :admin}]
  }
]

for org_data <- organizations_data do
  if org_data.owner do
    # Generate expected slug
    slug_to_find =
      org_data.name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")

    existing_org =
      JidoHub.Organizations.Organization
      |> Ash.Query.filter(expr(slug == ^slug_to_find))
      |> Ash.read_one(domain: JidoHub.Organizations, authorize?: false)

    organization =
      case existing_org do
        {:ok, nil} ->
          # Create organization using admin action
          {:ok, org} =
            JidoHub.Organizations.Organization
            |> Ash.Changeset.for_create(:admin_create, %{
              name: org_data.name,
              description: org_data.description,
              owner_id: org_data.owner.id
            })
            |> Ash.create(domain: JidoHub.Organizations, authorize?: false)

          IO.puts("Created organization: #{org.name} (#{org.slug})")
          org

        {:ok, org} ->
          IO.puts("Organization already exists: #{org.name} (#{org.slug})")
          org

        {:error, error} ->
          IO.puts("Error checking for organization: #{inspect(error)}")
          nil
      end

    if organization do
      # Create memberships for members (owner is implicit)
      for {member_user, role} <- org_data.members do
        if member_user do
          case SeedHelpers.ensure_membership(member_user.id, organization.id, role) do
            {:created, _membership} ->
              IO.puts("  - Added #{member_user.email} as #{role}")

            {:updated, _membership} ->
              IO.puts("  - Updated #{member_user.email} to #{role}")

            {:unchanged, _membership} ->
              IO.puts("  - #{member_user.email} already #{role}")

            {:error, error} ->
              IO.puts("  - Error adding #{member_user.email}: #{inspect(error)}")
          end
        end
      end
    end
  else
    IO.puts("Error: Owner not found for organization: #{org_data.name}")
  end
end

IO.puts("\n=== Organizations Setup Complete ===")
IO.puts("Total organizations created/verified: #{length(organizations_data)}")

# Create global admin user (idempotent)
IO.puts("\n=== Setting up Global Admin ===")

admin_email = "mike@epicfirm.com"
admin_user = SeedHelpers.get_user_by_email(admin_email)

case admin_user do
  nil ->
    # Create admin user
    {:ok, user} =
      JidoHub.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: admin_email,
        username: "mike",
        password: "password123",
        password_confirmation: "password123"
      })
      |> Ash.create(domain: JidoHub.Accounts, authorize?: false)

    # Grant admin role
    {:ok, _admin_user} =
      user
      |> Ash.Changeset.for_update(:update, %{role: :admin})
      |> Ash.update(domain: JidoHub.Accounts, authorize?: false)

    IO.puts("Created admin user: #{admin_email}")

  user ->
    if user.role == :admin do
      IO.puts("Admin already set: #{admin_email}")
    else
      # Grant admin role
      {:ok, _admin_user} =
        user
        |> Ash.Changeset.for_update(:update, %{role: :admin})
        |> Ash.update(domain: JidoHub.Accounts, authorize?: false)

      IO.puts("Granted admin to: #{admin_email}")
    end
end
