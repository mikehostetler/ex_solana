defmodule JidoHub.Pods.Pod.ChangesTest do
  use JidoHub.DataCase

  alias JidoHub.Accounts
  alias JidoHub.Organizations
  alias JidoHub.Pods
  alias JidoHub.Pods.Pod
  alias JidoHub.Pods.Pod.Changes.{GenerateSlug, ValidateOwner}

  describe "GenerateSlug.change/3 - basic slug generation" do
    test "generates slug from name" do
      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:name, "My Test Pod")

      result = GenerateSlug.change(changeset, [], %{})

      slug = Ash.Changeset.get_attribute(result, :slug)
      assert slug == "my-test-pod"
    end

    test "handles nil name" do
      changeset = Ash.Changeset.new(Pod)
      result = GenerateSlug.change(changeset, [], %{})

      slug = Ash.Changeset.get_attribute(result, :slug)
      assert slug == nil
    end

    test "downcases uppercase letters" do
      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:name, "UPPERCASE")

      result = GenerateSlug.change(changeset, [], %{})

      slug = Ash.Changeset.get_attribute(result, :slug)
      assert slug == "uppercase"
    end

    test "replaces spaces with hyphens" do
      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:name, "multiple words here")

      result = GenerateSlug.change(changeset, [], %{})

      slug = Ash.Changeset.get_attribute(result, :slug)
      assert slug == "multiple-words-here"
    end

    test "removes special characters" do
      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:name, "test@pod#123!")

      result = GenerateSlug.change(changeset, [], %{})

      slug = Ash.Changeset.get_attribute(result, :slug)
      assert slug == "testpod123"
    end

    test "collapses multiple hyphens" do
      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:name, "test---pod---name")

      result = GenerateSlug.change(changeset, [], %{})

      slug = Ash.Changeset.get_attribute(result, :slug)
      assert slug == "test-pod-name"
    end

    test "trims leading and trailing hyphens" do
      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:name, "---test-pod---")

      result = GenerateSlug.change(changeset, [], %{})

      slug = Ash.Changeset.get_attribute(result, :slug)
      assert slug == "test-pod"
    end

    test "handles numbers" do
      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:name, "Pod 123")

      result = GenerateSlug.change(changeset, [], %{})

      slug = Ash.Changeset.get_attribute(result, :slug)
      assert slug == "pod-123"
    end
  end

  describe "GenerateSlug.change/3 - uniqueness within owner context" do
    setup do
      {:ok, user} =
        Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "pod-owner@example.com",
          username: "podowner",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, org} =
        Organizations.Organization
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Test Org"
          },
          actor: user
        )
        |> Ash.create(domain: Organizations)

      %{user: user, org: org}
    end

    test "generates unique slug when duplicate exists for same owner", %{user: user} do
      {:ok, _existing} =
        Pod
        |> Ash.Changeset.for_create(:create, %{
          name: "Test Pod",
          owner_type: :user,
          owner_id: user.id
        })
        |> Ash.create(domain: Pods, actor: user, authorize?: false)

      {:ok, new_pod} =
        Pod
        |> Ash.Changeset.for_create(:create, %{
          name: "Test Pod",
          owner_type: :user,
          owner_id: user.id
        })
        |> Ash.create(domain: Pods, actor: user, authorize?: false)

      assert new_pod.slug == "test-pod-1"
    end

    test "allows same slug for different owners", %{user: user, org: org} do
      {:ok, user_pod} =
        Pod
        |> Ash.Changeset.for_create(:create, %{
          name: "Same Name",
          owner_type: :user,
          owner_id: user.id
        })
        |> Ash.create(domain: Pods, actor: user, authorize?: false)

      {:ok, org_pod} =
        Pod
        |> Ash.Changeset.for_create(:create, %{
          name: "Same Name",
          owner_type: :organization,
          owner_id: org.id
        })
        |> Ash.create(domain: Pods, actor: user, authorize?: false)

      assert user_pod.slug == "same-name"
      assert org_pod.slug == "same-name"
    end

    test "increments counter for multiple duplicates", %{user: user} do
      {:ok, _pod1} =
        Pod
        |> Ash.Changeset.for_create(:create, %{
          name: "Popular",
          owner_type: :user,
          owner_id: user.id
        })
        |> Ash.create(domain: Pods, actor: user, authorize?: false)

      {:ok, pod2} =
        Pod
        |> Ash.Changeset.for_create(:create, %{
          name: "Popular",
          owner_type: :user,
          owner_id: user.id
        })
        |> Ash.create(domain: Pods, actor: user, authorize?: false)

      {:ok, pod3} =
        Pod
        |> Ash.Changeset.for_create(:create, %{
          name: "Popular",
          owner_type: :user,
          owner_id: user.id
        })
        |> Ash.create(domain: Pods, actor: user, authorize?: false)

      assert pod2.slug == "popular-1"
      assert pod3.slug == "popular-2"
    end
  end

  describe "GenerateSlug.change/3 - slug preservation" do
    setup do
      {:ok, user} =
        Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "slug-test@example.com",
          username: "slugtest",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      %{user: user}
    end

    test "keeps existing slug if name doesn't change", %{user: user} do
      {:ok, pod} =
        Pod
        |> Ash.Changeset.for_create(:create, %{
          name: "Original Name",
          owner_type: :user,
          owner_id: user.id
        })
        |> Ash.create(domain: Pods, actor: user, authorize?: false)

      original_slug = pod.slug

      {:ok, updated_pod} =
        pod
        |> Ash.Changeset.for_update(:update, %{description: "New description"})
        |> Ash.update(domain: Pods, actor: user, authorize?: false)

      assert updated_pod.slug == original_slug
    end
  end

  describe "ValidateOwner.change/3 - user ownership" do
    setup do
      {:ok, user} =
        Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "validate-owner@example.com",
          username: "validateowner",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      %{user: user}
    end

    test "allows valid user owner", %{user: user} do
      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:owner_type, :user)
        |> Ash.Changeset.change_attribute(:owner_id, user.id)

      result = ValidateOwner.change(changeset, [], %{})

      assert result.valid?
      assert result.errors == []
    end

    test "rejects non-existent user owner" do
      fake_id = Ash.UUID.generate()

      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:owner_type, :user)
        |> Ash.Changeset.change_attribute(:owner_id, fake_id)

      result = ValidateOwner.change(changeset, [], %{})

      refute result.valid?

      assert Enum.any?(result.errors, fn e ->
               e.field == :owner_id && e.message == "User not found"
             end)
    end

    test "allows nil owner_type and owner_id" do
      changeset = Ash.Changeset.new(Pod)
      result = ValidateOwner.change(changeset, [], %{})

      assert result.valid?
      assert result.errors == []
    end
  end

  describe "ValidateOwner.change/3 - organization ownership" do
    setup do
      {:ok, user} =
        Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "org-owner@example.com",
          username: "orgowner",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, org} =
        Organizations.Organization
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Validate Org"
          },
          actor: user
        )
        |> Ash.create(domain: Organizations)

      %{user: user, org: org}
    end

    test "allows valid organization owner", %{org: org} do
      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:owner_type, :organization)
        |> Ash.Changeset.change_attribute(:owner_id, org.id)

      result = ValidateOwner.change(changeset, [], %{})

      assert result.valid?
      assert result.errors == []
    end

    test "rejects non-existent organization owner" do
      fake_id = Ash.UUID.generate()

      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:owner_type, :organization)
        |> Ash.Changeset.change_attribute(:owner_id, fake_id)

      result = ValidateOwner.change(changeset, [], %{})

      refute result.valid?

      assert Enum.any?(result.errors, fn e ->
               e.field == :owner_id && e.message == "Organization not found"
             end)
    end
  end

  describe "ValidateOwner.change/3 - partial owner data" do
    test "allows owner_type without owner_id" do
      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:owner_type, :user)

      result = ValidateOwner.change(changeset, [], %{})

      assert result.valid?
      assert result.errors == []
    end

    test "allows owner_id without owner_type" do
      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:owner_id, Ash.UUID.generate())

      result = ValidateOwner.change(changeset, [], %{})

      assert result.valid?
      assert result.errors == []
    end
  end
end
