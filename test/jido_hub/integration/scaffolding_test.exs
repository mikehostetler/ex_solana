defmodule JidoHub.Integration.ScaffoldingTest do
  use JidoHub.DataCase

  import JidoHub.Fixtures

  describe "test scaffolding and fixtures" do
    test "create_user! creates a user with given credentials" do
      user = create_user!("test@example.com", "testuser", "password123")

      assert to_string(user.email) == "test@example.com"
      assert user.username == "testuser"
      assert user.id
    end

    test "create_user! with no args creates a unique user" do
      user1 = create_user!()
      user2 = create_user!()

      assert user1.id
      assert user2.id
      assert user1.id != user2.id
      assert user1.email != user2.email
      assert user1.username != user2.username
    end

    test "create_org! creates an organization with owner" do
      user = create_user!()
      org = create_org!(user)

      assert org.id
      assert org.owner_id == user.id
      assert org.name
    end

    test "create_org! accepts custom attributes" do
      user = create_user!()
      org = create_org!(user, %{name: "Custom Org"})

      assert org.name == "Custom Org"
    end

    test "create_org_with_slug! creates org with specific slug" do
      user = create_user!()
      org = create_org_with_slug!(user, "my-custom-slug")

      assert org.slug == "my-custom-slug"
    end

    test "add_membership! adds user to org with given role" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)

      membership = add_membership!(org, member, :admin)

      assert membership.organization_id == org.id
      assert membership.user_id == member.id
      assert membership.role == :admin
    end

    test "create_pod! creates user-owned pod" do
      user = create_user!()
      pod = create_pod!(:user, user.id, %{name: "My Pod"}, user)

      assert pod.id
      assert pod.name == "My Pod"
      assert pod.owner_type == :user
      assert pod.owner_id == user.id
      assert pod.slug == "my-pod"
    end

    test "create_pod! creates org-owned pod" do
      user = create_user!()
      org = create_org!(user)
      pod = create_pod!(:organization, org.id, %{name: "Team Pod"}, user)

      assert pod.id
      assert pod.name == "Team Pod"
      assert pod.owner_type == :organization
      assert pod.owner_id == org.id
      assert pod.slug == "team-pod"
    end

    test "create_user_pod! convenience helper works" do
      user = create_user!()
      pod = create_user_pod!(user, "Quick Pod")

      assert pod.name == "Quick Pod"
      assert pod.owner_type == :user
      assert pod.owner_id == user.id
    end

    test "create_org_pod! convenience helper works" do
      user = create_user!()
      org = create_org!(user)
      pod = create_org_pod!(org, user, "Team Workspace")

      assert pod.name == "Team Workspace"
      assert pod.owner_type == :organization
      assert pod.owner_id == org.id
    end

    test "create_invitation! creates an invitation" do
      owner = create_user!()
      org = create_org!(owner)
      invitation = create_invitation!(org, owner, "invitee@example.com", :member)

      assert invitation.id
      assert invitation.organization_id == org.id
      assert invitation.invited_by_id == owner.id
      assert to_string(invitation.email) == "invitee@example.com"
      assert invitation.role == :member
      assert invitation.token
      assert invitation.expires_at
    end

    test "advance_time returns future DateTime" do
      now = DateTime.utc_now()
      future = advance_time(3600)

      assert DateTime.after?(future, now)
      diff = DateTime.diff(future, now)
      assert diff >= 3599
    end

    test "past_time returns past DateTime" do
      now = DateTime.utc_now()
      past = past_time(3600)

      assert DateTime.before?(past, now)
      diff = DateTime.diff(now, past)
      assert diff >= 3599
    end

    test "reload! reloads a resource from database" do
      user = create_user!()
      reloaded = reload!(user)

      assert reloaded.id == user.id
      assert to_string(reloaded.email) == to_string(user.email)
    end

    test "email helpers work with Swoosh.TestAdapter" do
      clear_emails!()
      emails = sent_emails()
      assert emails == []
    end
  end

  describe "integration with existing tests patterns" do
    test "follows Ash action patterns with actor" do
      user = create_user!()
      org = create_org!(user)

      # Verify we can use actor parameter in further operations
      pod =
        JidoHub.Pods.Pod
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Actor Test Pod",
            owner_type: :organization,
            owner_id: org.id
          },
          actor: user
        )
        |> Ash.create!(domain: JidoHub.Pods)

      assert pod.owner_id == org.id
    end

    test "fixtures work with authorize?: false for setup" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      membership = add_membership!(org, member, :member)

      # Verify membership was created without authorization
      assert membership.role == :member

      # Now test with authorization - member cannot create pods for org
      assert {:error, %Ash.Error.Forbidden{}} =
               JidoHub.Pods.Pod
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "Should Fail",
                   owner_type: :organization,
                   owner_id: org.id
                 },
                 actor: member
               )
               |> Ash.create(domain: JidoHub.Pods)
    end
  end
end
