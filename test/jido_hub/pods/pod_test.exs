defmodule JidoHub.Pods.PodTest do
  use JidoHub.DataCase

  import JidoHub.Fixtures

  alias JidoHub.Pods
  alias JidoHub.Pods.Pod

  describe "pod creation" do
    test "user can create personal pod" do
      user = create_user!()

      assert {:ok, pod} =
               Pod
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "My Workspace",
                   owner_type: :user,
                   owner_id: user.id
                 },
                 actor: user
               )
               |> Ash.create(domain: Pods)

      assert pod.name == "My Workspace"
      assert pod.slug == "my-workspace"
      assert pod.owner_type == :user
      assert pod.owner_id == user.id
    end

    test "org admin can create org pod" do
      user = create_user!()
      org = create_org!(user)

      assert {:ok, pod} =
               Pod
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "Team Workspace",
                   owner_type: :organization,
                   owner_id: org.id
                 },
                 actor: user
               )
               |> Ash.create(domain: Pods)

      assert pod.owner_type == :organization
      assert pod.owner_id == org.id
    end

    test "non-admin cannot create org pod" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      add_membership!(org, member, :member)

      assert {:error, %Ash.Error.Forbidden{}} =
               Pod
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "Team Workspace",
                   owner_type: :organization,
                   owner_id: org.id
                 },
                 actor: member
               )
               |> Ash.create(domain: Pods)
    end

    test "slug uniqueness behavior" do
      test_cases = [
        %{
          description: "same owner + same name twice generates -1 suffix",
          setup: fn ->
            user = create_user!()
            pod1 = create_user_pod!(user, "My Project")
            pod2 = create_user_pod!(user, "My Project")
            {pod1, pod2}
          end,
          assertions: fn {pod1, pod2} ->
            assert pod1.slug == "my-project"
            assert pod2.slug == "my-project-1"
          end
        },
        %{
          description: "different owners can have same slug",
          setup: fn ->
            user1 = create_user!()
            user2 = create_user!()
            pod1 = create_user_pod!(user1, "shared-name")
            pod2 = create_user_pod!(user2, "shared-name")
            {pod1, pod2}
          end,
          assertions: fn {pod1, pod2} ->
            assert pod1.slug == "shared-name"
            assert pod2.slug == "shared-name"
            assert pod1.owner_id != pod2.owner_id
          end
        },
        %{
          description: "rename to existing slug generates unique suffix",
          setup: fn ->
            user = create_user!()
            pod1 = create_user_pod!(user, "My Project")
            pod2 = create_user_pod!(user, "Another Project")

            {:ok, renamed} =
              pod2
              |> Ash.Changeset.for_update(:update, %{name: "My Project"}, actor: user)
              |> Ash.update(domain: Pods)

            {pod1, renamed}
          end,
          assertions: fn {pod1, renamed} ->
            assert pod1.slug == "my-project"
            assert renamed.slug != pod1.slug
            assert renamed.slug =~ ~r/^my-project-\d+$/
          end
        }
      ]

      for test_case <- test_cases do
        result = test_case.setup.()
        test_case.assertions.(result)
      end
    end

    test "validates owner exists" do
      user = create_user!()
      fake_id = Ash.UUID.generate()

      assert {:error, error} =
               Pod
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "Test Pod",
                   owner_type: :user,
                   owner_id: fake_id
                 },
                 actor: user
               )
               |> Ash.create(domain: Pods)

      assert error.errors
             |> Enum.any?(fn e ->
               e.field == :owner_id && String.contains?(e.message || "", "not found")
             end)
    end
  end

  describe "pod queries" do
    test "get pod by slug" do
      user = create_user!()
      pod = create_user_pod!(user, "Test Pod")

      assert {:ok, [found]} =
               Pod
               |> Ash.Query.for_read(:by_slug, %{
                 owner_type: :user,
                 owner_id: user.id,
                 slug: "test-pod"
               })
               |> Ash.read(domain: Pods, actor: user)

      assert found.id == pod.id
    end

    test "list pods for owner" do
      user = create_user!()
      pod1 = create_user_pod!(user, "Pod One")
      pod2 = create_user_pod!(user, "Pod Two")

      assert {:ok, pods} =
               Pod
               |> Ash.Query.for_read(:for_owner, %{
                 owner_type: :user,
                 owner_id: user.id
               })
               |> Ash.read(domain: Pods, actor: user)

      pod_ids = Enum.map(pods, & &1.id)
      assert pod1.id in pod_ids
      assert pod2.id in pod_ids
    end
  end

  describe "pod calculations" do
    test "full_path for user pod" do
      user = create_user_with_username!("testuser")
      pod = create_user_pod!(user, "My Pod")

      pod = Ash.load!(pod, :full_path, domain: Pods)
      assert pod.full_path == "@testuser/my-pod"
    end

    test "full_path for org pod" do
      user = create_user!()
      org = create_org_with_slug!(user, "test-org")

      {:ok, pod} =
        Pod
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Team Pod",
            owner_type: :organization,
            owner_id: org.id
          },
          actor: user
        )
        |> Ash.create(domain: Pods)

      pod = Ash.load!(pod, :full_path, domain: Pods)
      assert pod.full_path == "@test-org/team-pod"
    end
  end

  describe "authorization" do
    test "anyone can read public pods" do
      owner = create_user!()
      reader = create_user!()
      pod = create_user_pod!(owner, "Public Pod", visibility: :public)

      assert {:ok, found} = Ash.get(Pod, pod.id, domain: Pods, actor: reader)
      assert found.id == pod.id
    end

    test "user pod authorization matrix" do
      owner = create_user!()
      other = create_user!()
      pod = create_user_pod!(owner, "My Pod")

      test_cases = [
        %{actor: owner, action: :update, params: %{description: "Updated"}, should_succeed: true},
        %{actor: other, action: :update, params: %{description: "Hacked"}, should_succeed: false},
        %{actor: owner, action: :destroy, params: %{}, should_succeed: true}
      ]

      for %{actor: actor, action: action, params: params, should_succeed: should_succeed} <-
            test_cases do
        result =
          case action do
            :update ->
              pod
              |> Ash.Changeset.for_update(action, params, actor: actor)
              |> Ash.update(domain: Pods)

            :destroy ->
              pod
              |> Ash.Changeset.for_destroy(action, params, actor: actor)
              |> Ash.destroy(domain: Pods)
          end

        if should_succeed do
          case action do
            :update ->
              assert {:ok, updated} = result
              assert updated.description == params.description

            :destroy ->
              assert :ok = result
          end
        else
          assert {:error, %Ash.Error.Forbidden{}} = result
        end
      end
    end

    test "org pod authorization matrix" do
      owner = create_user!()
      admin = create_user!()
      member = create_user!()
      org = create_org!(owner)
      add_membership!(org, admin, :admin)
      add_membership!(org, member, :member)

      {:ok, pod} =
        Pod
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Org Pod",
            owner_type: :organization,
            owner_id: org.id
          },
          actor: owner
        )
        |> Ash.create(domain: Pods)

      test_cases = [
        %{
          actor: admin,
          action: :update,
          params: %{description: "Admin update"},
          should_succeed: true
        },
        %{actor: member, action: :destroy, params: %{}, should_succeed: false},
        %{actor: admin, action: :destroy, params: %{}, should_succeed: true}
      ]

      for %{actor: actor, action: action, params: params, should_succeed: should_succeed} <-
            test_cases do
        result =
          case action do
            :update ->
              pod
              |> Ash.Changeset.for_update(action, params, actor: actor)
              |> Ash.update(domain: Pods)

            :destroy ->
              pod
              |> Ash.Changeset.for_destroy(action, params, actor: actor)
              |> Ash.destroy(domain: Pods)
          end

        if should_succeed do
          case action do
            :update ->
              assert {:ok, updated} = result
              assert updated.description == params.description

            :destroy ->
              assert :ok = result
          end
        else
          assert {:error, %Ash.Error.Forbidden{}} = result
        end
      end
    end
  end

  describe "validation errors" do
    test "missing owner_type returns error" do
      user = create_user!()

      result =
        Pod
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Test Pod",
            owner_id: user.id
          },
          actor: user
        )
        |> Ash.create(domain: Pods)

      assert {:error, error} = result

      assert error.errors
             |> Enum.any?(fn e ->
               e.field == :owner_type
             end)
    end

    test "missing owner_id returns error" do
      user = create_user!()

      result =
        Pod
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Test Pod",
            owner_type: :user
          },
          actor: user
        )
        |> Ash.create(domain: Pods)

      assert {:error, error} = result

      assert error.errors
             |> Enum.any?(fn e ->
               e.field == :owner_id
             end)
    end

    test "invalid owner_type returns error" do
      user = create_user!()

      assert {:error, error} =
               Pod
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "Test Pod",
                   owner_type: :invalid,
                   owner_id: user.id
                 },
                 actor: user
               )
               |> Ash.create(domain: Pods)

      assert error.errors
             |> Enum.any?(fn e ->
               e.field == :owner_type
             end)
    end
  end

  describe "slug generation and conflicts" do
    test "updating pod name regenerates slug" do
      user = create_user!()
      pod = create_user_pod!(user, "Original Name")

      assert pod.slug == "original-name"

      {:ok, updated} =
        pod
        |> Ash.Changeset.for_update(:update, %{name: "New Name"}, actor: user)
        |> Ash.update(domain: Pods)

      assert updated.slug == "new-name"
    end
  end

  describe "settings and metadata" do
    test "pod can be created with settings" do
      user = create_user!()

      {:ok, pod} =
        Pod
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Pod with settings",
            owner_type: :user,
            owner_id: user.id
          },
          actor: user
        )
        |> Ash.create(domain: Pods)

      assert pod.settings == %{}

      {:ok, updated} =
        pod
        |> Ash.Changeset.for_update(:update, %{settings: %{theme: "dark", language: "en"}},
          actor: user
        )
        |> Ash.update(domain: Pods)

      assert updated.settings == %{"theme" => "dark", "language" => "en"}
    end

    test "metadata defaults to empty map" do
      user = create_user!()
      pod = create_user_pod!(user, "Test Pod")

      assert pod.metadata == %{}
    end
  end
end
