defmodule JidoHub.Integration.OrganizationPoliciesTest do
  use JidoHub.DataCase

  import JidoHub.Fixtures

  alias JidoHub.Organizations

  describe "organization access control" do
    test "owner can read organization" do
      owner = create_user!()
      org = create_org!(owner)

      {:ok, fetched} =
        Organizations.Organization
        |> Ash.get(org.id, domain: Organizations, actor: owner)

      assert fetched.id == org.id
      assert fetched.name == org.name
    end

    test "members can read organization" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      add_membership!(org, member, :member)

      {:ok, fetched} =
        Organizations.Organization
        |> Ash.get(org.id, domain: Organizations, actor: member)

      assert fetched.id == org.id
    end

    test "admin can read organization" do
      owner = create_user!()
      admin = create_user!()
      org = create_org!(owner)
      add_membership!(org, admin, :admin)

      {:ok, fetched} =
        Organizations.Organization
        |> Ash.get(org.id, domain: Organizations, actor: admin)

      assert fetched.id == org.id
    end

    test "non-members cannot read organization" do
      owner = create_user!()
      non_member = create_user!()
      org = create_org!(owner)

      assert {:error, %Ash.Error.Invalid{}} =
               Organizations.Organization
               |> Ash.get(org.id, domain: Organizations, actor: non_member)
    end

    test "only owner can update organization" do
      owner = create_user!()
      org = create_org!(owner)

      {:ok, updated} =
        org
        |> Ash.Changeset.for_update(:update, %{name: "Updated Name"}, actor: owner)
        |> Ash.update(domain: Organizations)

      assert updated.name == "Updated Name"
      assert updated.slug == "updated-name"
    end

    test "admin cannot update organization" do
      owner = create_user!()
      admin = create_user!()
      org = create_org!(owner)
      add_membership!(org, admin, :admin)

      assert {:error, %Ash.Error.Forbidden{}} =
               org
               |> Ash.Changeset.for_update(:update, %{name: "Updated Name"}, actor: admin)
               |> Ash.update(domain: Organizations)
    end

    test "member cannot update organization" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      add_membership!(org, member, :member)

      assert {:error, %Ash.Error.Forbidden{}} =
               org
               |> Ash.Changeset.for_update(:update, %{name: "Updated Name"}, actor: member)
               |> Ash.update(domain: Organizations)
    end

    test "only owner can destroy organization" do
      owner = create_user!()
      org = create_org!(owner)

      :ok =
        org
        |> Ash.Changeset.for_destroy(:destroy, %{}, actor: owner)
        |> Ash.destroy(domain: Organizations)

      assert {:error, %Ash.Error.Invalid{}} =
               Organizations.Organization
               |> Ash.get(org.id, domain: Organizations, authorize?: false)
    end

    test "admin cannot destroy organization" do
      owner = create_user!()
      admin = create_user!()
      org = create_org!(owner)
      add_membership!(org, admin, :admin)

      assert {:error, %Ash.Error.Forbidden{}} =
               org
               |> Ash.Changeset.for_destroy(:destroy, %{}, actor: admin)
               |> Ash.destroy(domain: Organizations)
    end

    test "member cannot destroy organization" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      add_membership!(org, member, :member)

      assert {:error, %Ash.Error.Forbidden{}} =
               org
               |> Ash.Changeset.for_destroy(:destroy, %{}, actor: member)
               |> Ash.destroy(domain: Organizations)
    end
  end

  describe "organization ownership transfer" do
    test "only current owner can transfer ownership" do
      owner = create_user!()
      new_owner = create_user!()
      org = create_org!(owner)
      add_membership!(org, new_owner, :member)

      {:ok, updated} =
        org
        |> Ash.Changeset.for_update(
          :transfer_ownership,
          %{new_owner_id: new_owner.id},
          actor: owner
        )
        |> Ash.update(domain: Organizations)

      assert updated.owner_id == new_owner.id
    end

    test "new owner can update organization after transfer" do
      owner = create_user!()
      new_owner = create_user!()
      org = create_org!(owner)
      add_membership!(org, new_owner, :member)

      {:ok, transferred} =
        org
        |> Ash.Changeset.for_update(
          :transfer_ownership,
          %{new_owner_id: new_owner.id},
          actor: owner
        )
        |> Ash.update(domain: Organizations)

      {:ok, updated} =
        transferred
        |> Ash.Changeset.for_update(:update, %{name: "New Owner Updated"}, actor: new_owner)
        |> Ash.update(domain: Organizations)

      assert updated.name == "New Owner Updated"
    end

    test "new owner can destroy organization after transfer" do
      owner = create_user!()
      new_owner = create_user!()
      org = create_org!(owner)

      {:ok, transferred} =
        org
        |> Ash.Changeset.for_update(
          :transfer_ownership,
          %{new_owner_id: new_owner.id},
          actor: owner
        )
        |> Ash.update(domain: Organizations)

      :ok =
        transferred
        |> Ash.Changeset.for_destroy(:destroy, %{}, actor: new_owner)
        |> Ash.destroy(domain: Organizations)

      assert {:error, %Ash.Error.Invalid{}} =
               Organizations.Organization
               |> Ash.get(org.id, domain: Organizations, authorize?: false)
    end

    test "previous owner cannot update after transfer" do
      owner = create_user!()
      new_owner = create_user!()
      org = create_org!(owner)
      add_membership!(org, new_owner, :member)

      {:ok, transferred} =
        org
        |> Ash.Changeset.for_update(
          :transfer_ownership,
          %{new_owner_id: new_owner.id},
          actor: owner
        )
        |> Ash.update(domain: Organizations)

      assert {:error, %Ash.Error.Forbidden{}} =
               transferred
               |> Ash.Changeset.for_update(:update, %{name: "Old Owner Update"}, actor: owner)
               |> Ash.update(domain: Organizations)
    end

    test "previous owner cannot destroy after transfer" do
      owner = create_user!()
      new_owner = create_user!()
      org = create_org!(owner)
      add_membership!(org, new_owner, :member)

      {:ok, transferred} =
        org
        |> Ash.Changeset.for_update(
          :transfer_ownership,
          %{new_owner_id: new_owner.id},
          actor: owner
        )
        |> Ash.update(domain: Organizations)

      assert {:error, %Ash.Error.Forbidden{}} =
               transferred
               |> Ash.Changeset.for_destroy(:destroy, %{}, actor: owner)
               |> Ash.destroy(domain: Organizations)
    end

    test "admin cannot transfer ownership" do
      owner = create_user!()
      admin = create_user!()
      new_owner = create_user!()
      org = create_org!(owner)
      add_membership!(org, admin, :admin)
      add_membership!(org, new_owner, :member)

      assert {:error, %Ash.Error.Forbidden{}} =
               org
               |> Ash.Changeset.for_update(
                 :transfer_ownership,
                 %{new_owner_id: new_owner.id},
                 actor: admin
               )
               |> Ash.update(domain: Organizations)
    end

    test "member cannot transfer ownership" do
      owner = create_user!()
      member = create_user!()
      new_owner = create_user!()
      org = create_org!(owner)
      add_membership!(org, member, :member)
      add_membership!(org, new_owner, :member)

      assert {:error, %Ash.Error.Forbidden{}} =
               org
               |> Ash.Changeset.for_update(
                 :transfer_ownership,
                 %{new_owner_id: new_owner.id},
                 actor: member
               )
               |> Ash.update(domain: Organizations)
    end

    test "non-member cannot transfer ownership" do
      owner = create_user!()
      non_member = create_user!()
      new_owner = create_user!()
      org = create_org!(owner)

      assert {:error, %Ash.Error.Forbidden{}} =
               org
               |> Ash.Changeset.for_update(
                 :transfer_ownership,
                 %{new_owner_id: new_owner.id},
                 actor: non_member
               )
               |> Ash.update(domain: Organizations)
    end
  end

  describe "organization lifecycle" do
    test "organization can be created, updated, and destroyed" do
      owner = create_user!()

      {:ok, org} =
        Organizations.Organization
        |> Ash.Changeset.for_create(:create, %{name: "Test Org"}, actor: owner)
        |> Ash.create(domain: Organizations)

      assert org.name == "Test Org"
      assert org.slug == "test-org"

      {:ok, updated} =
        org
        |> Ash.Changeset.for_update(:update, %{description: "A description"}, actor: owner)
        |> Ash.update(domain: Organizations)

      assert updated.description == "A description"

      :ok =
        updated
        |> Ash.Changeset.for_destroy(:destroy, %{}, actor: owner)
        |> Ash.destroy(domain: Organizations)

      assert {:error, %Ash.Error.Invalid{}} =
               Organizations.Organization
               |> Ash.get(org.id, domain: Organizations, authorize?: false)
    end

    test "organization owner can read after adding members" do
      owner = create_user!()
      member1 = create_user!()
      member2 = create_user!()
      org = create_org!(owner)

      add_membership!(org, member1, :member)
      add_membership!(org, member2, :admin)

      {:ok, fetched} =
        Organizations.Organization
        |> Ash.get(org.id, domain: Organizations, actor: owner)

      assert fetched.id == org.id
    end

    test "organization settings can be updated by owner" do
      owner = create_user!()
      org = create_org!(owner)

      {:ok, updated} =
        org
        |> Ash.Changeset.for_update(
          :update,
          %{settings: %{theme: "dark", notifications: true}},
          actor: owner
        )
        |> Ash.update(domain: Organizations)

      assert updated.settings == %{"theme" => "dark", "notifications" => true}
    end

    test "organization description can be updated by owner" do
      owner = create_user!()
      org = create_org!(owner, %{description: "Original description"})

      {:ok, updated} =
        org
        |> Ash.Changeset.for_update(
          :update,
          %{description: "Updated description"},
          actor: owner
        )
        |> Ash.update(domain: Organizations)

      assert updated.description == "Updated description"
    end
  end
end
