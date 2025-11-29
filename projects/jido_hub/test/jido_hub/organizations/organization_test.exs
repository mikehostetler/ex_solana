defmodule JidoHub.Organizations.OrganizationTest do
  use JidoHub.DataCase

  import JidoHub.Fixtures

  alias JidoHub.Organizations.Organization

  describe "create/2" do
    test "creates organization with valid attributes" do
      user = create_user!()

      {:ok, organization} =
        Organization
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Test Organization",
            description: "A test organization"
          },
          actor: user
        )
        |> Ash.create(domain: JidoHub.Organizations)

      assert organization.name == "Test Organization"
      assert organization.description == "A test organization"
      assert organization.owner_id == user.id
      assert organization.slug == "test-organization"
    end

    test "generates unique slug when name conflicts" do
      user = create_user!()

      {:ok, _org1} =
        Organization
        |> Ash.Changeset.for_create(:create, %{name: "Test Organization"}, actor: user)
        |> Ash.create(domain: JidoHub.Organizations)

      {:ok, org2} =
        Organization
        |> Ash.Changeset.for_create(:create, %{name: "Test Organization"}, actor: user)
        |> Ash.create(domain: JidoHub.Organizations)

      assert org2.slug == "test-organization-1"
    end

    test "requires name" do
      user = create_user!()

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Organization
               |> Ash.Changeset.for_create(:create, %{description: "No name"}, actor: user)
               |> Ash.create(domain: JidoHub.Organizations)

      assert Enum.any?(errors, &(&1.field == :name))
    end

    test "validates name length" do
      user = create_user!()

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Organization
               |> Ash.Changeset.for_create(:create, %{name: ""}, actor: user)
               |> Ash.create(domain: JidoHub.Organizations)

      assert Enum.any?(errors, &(&1.field == :name))
    end
  end

  describe "update/2" do
    test "updates organization name and regenerates slug" do
      user = create_user!()
      organization = create_organization!(user, %{name: "Old Name"})

      {:ok, updated} =
        organization
        |> Ash.Changeset.for_update(:update, %{name: "New Name"})
        |> Ash.update(domain: JidoHub.Organizations, actor: user)

      assert updated.name == "New Name"
      assert updated.slug == "new-name"
    end
  end

  describe "create authorization" do
    test "owner_id is set to actor regardless of input" do
      user = create_user!()
      _other_user = create_user!()

      # Owner_id cannot be passed as input since it's not writable
      # The actor is always set as the owner via relate_actor
      {:ok, organization} =
        Organization
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Test Org"
          },
          actor: user
        )
        |> Ash.create(domain: JidoHub.Organizations)

      assert organization.owner_id == user.id
    end

    test "unauthenticated users cannot create organizations" do
      # When no actor is provided, relate_actor fails with Invalid error
      # before the authorization policy is checked
      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.InvalidRelationship{}]}} =
               Organization
               |> Ash.Changeset.for_create(:create, %{name: "Test Org"})
               |> Ash.create(domain: JidoHub.Organizations)
    end

    test "authenticated users can create organizations with themselves as owner" do
      user = create_user!()

      {:ok, organization} =
        Organization
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "My Organization",
            description: "Test organization"
          },
          actor: user
        )
        |> Ash.create(domain: JidoHub.Organizations)

      assert organization.owner_id == user.id
      assert organization.name == "My Organization"
    end
  end

  describe "read authorization" do
    test "owner and members can read, non-members cannot" do
      owner = create_user!()
      member = create_user!()
      non_member = create_user!()
      organization = create_organization!(owner)
      create_membership!(organization, member, :member)

      for {actor, description, expected} <- [
            {owner, "owner", :ok},
            {member, "member", :ok},
            {non_member, "non-member", :error}
          ] do
        result =
          Ash.get(Organization, organization.id,
            domain: JidoHub.Organizations,
            actor: actor
          )

        case expected do
          :ok ->
            assert {:ok, fetched} = result, "#{description} should read organization"
            assert fetched.id == organization.id

          :error ->
            assert {:error, %Ash.Error.Invalid{}} = result,
                   "#{description} should not read organization"
        end
      end
    end

    test "update: only owner can update" do
      owner = create_user!()
      member = create_user!()
      non_member = create_user!()
      organization = create_organization!(owner)
      create_membership!(organization, member, :member)

      for {actor, description, expected} <- [
            {owner, "owner", :ok},
            {member, "member", :forbidden},
            {non_member, "non-member", :forbidden}
          ] do
        result =
          organization
          |> Ash.Changeset.for_update(:update, %{name: "Updated Name"})
          |> Ash.update(domain: JidoHub.Organizations, actor: actor)

        case expected do
          :ok ->
            assert {:ok, updated} = result, "#{description} should update organization"
            assert updated.name == "Updated Name"

          :forbidden ->
            assert {:error, %Ash.Error.Forbidden{}} = result,
                   "#{description} should not update organization"
        end
      end
    end

    test "destroy: only owner can delete, even admins cannot" do
      owner = create_user!()
      admin = create_user!()
      non_member = create_user!()
      org1 = create_organization!(owner)
      org2 = create_organization!(owner)
      org3 = create_organization!(owner)
      create_membership!(org2, admin, :admin)

      for {org, actor, description, expected} <- [
            {org1, owner, "owner", :ok},
            {org2, admin, "admin member", :forbidden},
            {org3, non_member, "non-member", :forbidden}
          ] do
        result =
          org
          |> Ash.Changeset.for_destroy(:destroy)
          |> Ash.destroy(domain: JidoHub.Organizations, actor: actor)

        case expected do
          :ok ->
            assert :ok = result, "#{description} should delete organization"

          :forbidden ->
            assert {:error, %Ash.Error.Forbidden{}} = result,
                   "#{description} should not delete organization"
        end
      end
    end
  end

  describe "transfer_ownership/2" do
    test "owner can transfer ownership to another user (writable? false doesn't break it)" do
      owner = create_user!()
      new_owner = create_user!()
      organization = create_organization!(owner)

      {:ok, transferred} =
        organization
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:new_owner_id, new_owner.id)
        |> Ash.Changeset.for_update(:transfer_ownership, %{})
        |> Ash.update(domain: JidoHub.Organizations, actor: owner)

      assert transferred.owner_id == new_owner.id
    end

    test "transfer_ownership uses argument, not direct attribute setting" do
      owner = create_user!()
      new_owner = create_user!()
      organization = create_organization!(owner)

      {:ok, transferred} =
        organization
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:new_owner_id, new_owner.id)
        |> Ash.Changeset.for_update(:transfer_ownership, %{})
        |> Ash.update(domain: JidoHub.Organizations, actor: owner)

      assert transferred.owner_id == new_owner.id

      # Reload to verify persistence
      {:ok, reloaded} =
        Ash.get(Organization, organization.id, domain: JidoHub.Organizations, actor: new_owner)

      assert reloaded.owner_id == new_owner.id
    end

    test "non-owner cannot transfer ownership" do
      owner = create_user!()
      other_user = create_user!()
      new_owner = create_user!()
      organization = create_organization!(owner)

      assert {:error, %Ash.Error.Forbidden{}} =
               organization
               |> Ash.Changeset.new()
               |> Ash.Changeset.set_argument(:new_owner_id, new_owner.id)
               |> Ash.Changeset.for_update(:transfer_ownership, %{})
               |> Ash.update(domain: JidoHub.Organizations, actor: other_user)
    end
  end

  describe "slug normalization" do
    test "normalizes names with various formats" do
      base = System.unique_integer([:positive])

      test_cases = [
        {"Test! Org#123-#{base}-1", "test-org123-#{base}-1", "special characters"},
        {"Test   Organization-#{base}-2", "test-organization-#{base}-2", "multiple spaces"},
        {"TEST ORGANIZATION-#{base}-3", "test-organization-#{base}-3", "uppercase"}
      ]

      for {input_name, expected_slug, description} <- test_cases do
        user = create_user!()

        {:ok, organization} =
          Organization
          |> Ash.Changeset.for_create(:create, %{name: input_name}, actor: user)
          |> Ash.create(domain: JidoHub.Organizations)

        assert organization.slug == expected_slug,
               "failed to normalize #{description}: expected #{expected_slug}, got #{organization.slug}"
      end
    end
  end
end
