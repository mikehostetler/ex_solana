defmodule JidoHub.Pods.Pod.CalculationsTest do
  use JidoHub.DataCase

  alias JidoHub.Accounts
  alias JidoHub.Organizations
  alias JidoHub.Pods
  alias JidoHub.Pods.Pod
  alias JidoHub.Pods.Pod.Calculations.Owner

  describe "Owner.calculate/3 - user ownership" do
    setup do
      {:ok, user} =
        Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "calc-user@example.com",
          username: "calcuser",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, pod} =
        Pod
        |> Ash.Changeset.for_create(:create, %{
          name: "User Pod",
          owner_type: :user,
          owner_id: user.id
        })
        |> Ash.create(domain: Pods, actor: user, authorize?: false)

      %{user: user, pod: pod}
    end

    test "returns user data for user-owned pod", %{user: user, pod: pod} do
      records = [pod]
      [result] = Owner.calculate(records, [], %{domain: Pods})

      assert result != nil
      assert result.id == user.id
      assert result.email == user.email
      assert result.username == user.username
      assert Enum.sort(Map.keys(result)) == [:email, :id, :username]
    end

    test "returns only specified fields", %{pod: pod} do
      records = [pod]
      [result] = Owner.calculate(records, [], %{domain: Pods})

      refute Map.has_key?(result, :hashed_password)
      refute Map.has_key?(result, :inserted_at)
      refute Map.has_key?(result, :updated_at)
    end

    test "handles non-existent user gracefully" do
      fake_pod = %Pod{
        id: Ash.UUID.generate(),
        owner_type: :user,
        owner_id: Ash.UUID.generate(),
        name: "Orphan Pod",
        slug: "orphan-pod"
      }

      records = [fake_pod]
      [result] = Owner.calculate(records, [], %{domain: Pods})

      assert result == nil
    end
  end

  describe "Owner.calculate/3 - organization ownership" do
    setup do
      {:ok, user} =
        Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "calc-org@example.com",
          username: "calcorg",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, org} =
        Organizations.Organization
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Calc Org"
          },
          actor: user
        )
        |> Ash.create(domain: Organizations)

      {:ok, pod} =
        Pod
        |> Ash.Changeset.for_create(:create, %{
          name: "Org Pod",
          owner_type: :organization,
          owner_id: org.id
        })
        |> Ash.create(domain: Pods, actor: user, authorize?: false)

      %{user: user, org: org, pod: pod}
    end

    test "returns organization data for org-owned pod", %{org: org, pod: pod} do
      records = [pod]
      [result] = Owner.calculate(records, [], %{domain: Pods})

      assert result != nil
      assert result.id == org.id
      assert result.name == org.name
      assert result.slug == org.slug
      assert Enum.sort(Map.keys(result)) == [:id, :name, :slug]
    end

    test "returns only specified org fields", %{pod: pod} do
      records = [pod]
      [result] = Owner.calculate(records, [], %{domain: Pods})

      refute Map.has_key?(result, :inserted_at)
      refute Map.has_key?(result, :updated_at)
      refute Map.has_key?(result, :description)
    end

    test "handles non-existent organization gracefully" do
      fake_pod = %Pod{
        id: Ash.UUID.generate(),
        owner_type: :organization,
        owner_id: Ash.UUID.generate(),
        name: "Orphan Org Pod",
        slug: "orphan-org-pod"
      }

      records = [fake_pod]
      [result] = Owner.calculate(records, [], %{domain: Pods})

      assert result == nil
    end
  end

  describe "Owner.calculate/3 - multiple records" do
    setup do
      {:ok, user1} =
        Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "multi-user1@example.com",
          username: "multiuser1",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, user2} =
        Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "multi-user2@example.com",
          username: "multiuser2",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, org} =
        Organizations.Organization
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Multi Org"
          },
          actor: user1
        )
        |> Ash.create(domain: Organizations)

      {:ok, pod1} =
        Pod
        |> Ash.Changeset.for_create(:create, %{
          name: "Pod 1",
          owner_type: :user,
          owner_id: user1.id
        })
        |> Ash.create(domain: Pods, actor: user1, authorize?: false)

      {:ok, pod2} =
        Pod
        |> Ash.Changeset.for_create(:create, %{
          name: "Pod 2",
          owner_type: :user,
          owner_id: user2.id
        })
        |> Ash.create(domain: Pods, actor: user2, authorize?: false)

      {:ok, pod3} =
        Pod
        |> Ash.Changeset.for_create(:create, %{
          name: "Pod 3",
          owner_type: :organization,
          owner_id: org.id
        })
        |> Ash.create(domain: Pods, actor: user1, authorize?: false)

      %{user1: user1, user2: user2, org: org, pods: [pod1, pod2, pod3]}
    end

    test "calculates owners for multiple pods", %{
      user1: user1,
      user2: user2,
      org: org,
      pods: pods
    } do
      results = Owner.calculate(pods, [], %{domain: Pods})

      assert length(results) == 3

      [result1, result2, result3] = results

      assert result1.id == user1.id
      assert result1.email == user1.email

      assert result2.id == user2.id
      assert result2.email == user2.email

      assert result3.id == org.id
      assert result3.name == org.name
    end

    test "maintains order of input records", %{pods: pods} do
      results = Owner.calculate(pods, [], %{domain: Pods})
      assert length(results) == length(pods)
    end
  end

  describe "Owner.calculate/3 - empty and nil cases" do
    test "handles empty list" do
      results = Owner.calculate([], [], %{domain: Pods})
      assert results == []
    end

    test "handles pod with nil owner_type" do
      pod = %Pod{
        id: Ash.UUID.generate(),
        owner_type: nil,
        owner_id: Ash.UUID.generate(),
        name: "No Type Pod",
        slug: "no-type-pod"
      }

      assert_raise CaseClauseError, fn ->
        Owner.calculate([pod], [], %{domain: Pods})
      end
    end

    test "handles pod with nil owner_id gracefully" do
      pod = %Pod{
        id: Ash.UUID.generate(),
        owner_type: :user,
        owner_id: nil,
        name: "No ID Pod",
        slug: "no-id-pod"
      }

      [result] = Owner.calculate([pod], [], %{domain: Pods})
      assert result == nil
    end
  end

  describe "Owner.calculate/3 - mixed valid and invalid records" do
    setup do
      {:ok, user} =
        Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "mixed@example.com",
          username: "mixeduser",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, valid_pod} =
        Pod
        |> Ash.Changeset.for_create(:create, %{
          name: "Valid Pod",
          owner_type: :user,
          owner_id: user.id
        })
        |> Ash.create(domain: Pods, actor: user, authorize?: false)

      invalid_pod = %Pod{
        id: Ash.UUID.generate(),
        owner_type: :user,
        owner_id: Ash.UUID.generate(),
        name: "Invalid Pod",
        slug: "invalid-pod"
      }

      %{user: user, valid_pod: valid_pod, invalid_pod: invalid_pod}
    end

    test "returns nil for invalid records", %{
      user: user,
      valid_pod: valid_pod,
      invalid_pod: invalid_pod
    } do
      results = Owner.calculate([valid_pod, invalid_pod], [], %{domain: Pods})

      assert length(results) == 2
      [valid_result, invalid_result] = results

      assert valid_result.id == user.id
      assert invalid_result == nil
    end
  end
end
