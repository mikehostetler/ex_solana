# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Tool.ExecutionTest do
  use ExUnit.Case, async: true

  alias AshAi.Tool.Execution

  defmodule Post do
    use Ash.Resource,
      domain: __MODULE__.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :title, :string, allow_nil?: false, public?: true
      attribute :body, :string, public?: true
      attribute :view_count, :integer, default: 0, public?: true
      attribute :published, :boolean, default: false, public?: true
    end

    actions do
      defaults [:read, :destroy]

      create :create do
        accept [:title, :body, :published, :view_count]
      end

      update :update do
        accept [:title, :body, :view_count, :published]
      end

      update :publish do
        accept []
        change set_attribute(:published, true)
      end

      action :get_title, :string do
        argument :post_id, :uuid, allow_nil?: false

        run fn input, context ->
          post = Ash.get!(Post, input.arguments.post_id, domain: context.domain)
          {:ok, post.title}
        end
      end
    end

    calculations do
      calculate :title_length, :integer, expr(string_length(title))
    end

    defmodule Domain do
      use Ash.Domain

      resources do
        resource Post
      end
    end
  end

  setup do
    exec_ctx = %{
      actor: nil,
      tenant: nil,
      context: %{},
      tool_callbacks: %{},
      load: [],
      identity: nil,
      domain: Post.Domain
    }

    {:ok, exec_ctx: exec_ctx}
  end

  describe "run/4 with read actions" do
    test "executes read action with no arguments", %{exec_ctx: exec_ctx} do
      _post1 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "First", body: "Body 1"})
        |> Ash.create!()

      _post2 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "Second", body: "Body 2"})
        |> Ash.create!()

      action = Ash.Resource.Info.action(Post, :read)
      {:ok, json, raw} = Execution.run(Post, action, %{}, exec_ctx)

      assert is_binary(json)
      decoded = Jason.decode!(json)
      assert is_list(decoded)
      assert length(decoded) == 2

      assert is_list(raw)
      assert length(raw) == 2
    end

    test "executes read action with filter", %{exec_ctx: exec_ctx} do
      _post1 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "First", body: "Body 1"})
        |> Ash.create!()

      _post2 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "Second", body: "Body 2"})
        |> Ash.create!()

      action = Ash.Resource.Info.action(Post, :read)
      arguments = %{"filter" => %{"title" => "First"}}
      {:ok, json, raw} = Execution.run(Post, action, arguments, exec_ctx)

      decoded = Jason.decode!(json)
      assert length(decoded) == 1
      assert hd(decoded)["title"] == "First"

      assert length(raw) == 1
    end

    test "executes read action with sort", %{exec_ctx: exec_ctx} do
      _post1 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "Zebra", body: "Body 1"})
        |> Ash.create!()

      _post2 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "Apple", body: "Body 2"})
        |> Ash.create!()

      action = Ash.Resource.Info.action(Post, :read)
      arguments = %{"sort" => [%{"field" => "title", "direction" => "asc"}]}
      {:ok, json, _raw} = Execution.run(Post, action, arguments, exec_ctx)

      decoded = Jason.decode!(json)
      assert hd(decoded)["title"] == "Apple"
      assert List.last(decoded)["title"] == "Zebra"
    end

    test "executes read action with sort descending", %{exec_ctx: exec_ctx} do
      _post1 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "Zebra", body: "Body 1"})
        |> Ash.create!()

      _post2 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "Apple", body: "Body 2"})
        |> Ash.create!()

      action = Ash.Resource.Info.action(Post, :read)
      arguments = %{"sort" => [%{"field" => "title", "direction" => "desc"}]}
      {:ok, json, _raw} = Execution.run(Post, action, arguments, exec_ctx)

      decoded = Jason.decode!(json)
      assert hd(decoded)["title"] == "Zebra"
      assert List.last(decoded)["title"] == "Apple"
    end

    test "executes read action with limit", %{exec_ctx: exec_ctx} do
      for i <- 1..5 do
        Post
        |> Ash.Changeset.for_create(:create, %{title: "Post #{i}", body: "Body #{i}"})
        |> Ash.create!()
      end

      action = Ash.Resource.Info.action(Post, :read)
      arguments = %{"limit" => 2}
      {:ok, json, raw} = Execution.run(Post, action, arguments, exec_ctx)

      decoded = Jason.decode!(json)
      assert length(decoded) == 2
      assert length(raw) == 2
    end

    test "executes read action with offset", %{exec_ctx: exec_ctx} do
      for i <- 1..5 do
        Post
        |> Ash.Changeset.for_create(:create, %{title: "Post #{i}", body: "Body #{i}"})
        |> Ash.create!()
      end

      action = Ash.Resource.Info.action(Post, :read)
      arguments = %{"limit" => 2, "offset" => 2}
      {:ok, json, _raw} = Execution.run(Post, action, arguments, exec_ctx)

      decoded = Jason.decode!(json)
      assert length(decoded) == 2
    end

    test "executes read with result_type count", %{exec_ctx: exec_ctx} do
      for i <- 1..3 do
        Post
        |> Ash.Changeset.for_create(:create, %{title: "Post #{i}", body: "Body #{i}"})
        |> Ash.create!()
      end

      action = Ash.Resource.Info.action(Post, :read)
      arguments = %{"result_type" => "count"}
      {:ok, json, raw} = Execution.run(Post, action, arguments, exec_ctx)

      assert json == "3"
      assert raw == 3
    end

    test "executes read with result_type exists when records exist", %{exec_ctx: exec_ctx} do
      Post |> Ash.Changeset.for_create(:create, %{title: "Post", body: "Body"}) |> Ash.create!()

      action = Ash.Resource.Info.action(Post, :read)
      arguments = %{"result_type" => "exists"}
      {:ok, json, raw} = Execution.run(Post, action, arguments, exec_ctx)

      assert json == "true"
      assert raw == true
    end

    test "executes read with result_type exists when no records", %{exec_ctx: exec_ctx} do
      action = Ash.Resource.Info.action(Post, :read)
      arguments = %{"result_type" => "exists"}
      {:ok, json, raw} = Execution.run(Post, action, arguments, exec_ctx)

      assert json == "false"
      assert raw == false
    end

    test "executes read with aggregate max", %{exec_ctx: exec_ctx} do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "Post 1", body: "Body", view_count: 10})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "Post 2", body: "Body", view_count: 25})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "Post 3", body: "Body", view_count: 15})
      |> Ash.create!()

      action = Ash.Resource.Info.action(Post, :read)
      arguments = %{"result_type" => %{"aggregate" => "max", "field" => "view_count"}}
      {:ok, json, raw} = Execution.run(Post, action, arguments, exec_ctx)

      assert json == "25"
      assert raw == 25
    end

    test "executes read with aggregate min", %{exec_ctx: exec_ctx} do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "Post 1", body: "Body", view_count: 10})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "Post 2", body: "Body", view_count: 25})
      |> Ash.create!()

      action = Ash.Resource.Info.action(Post, :read)
      arguments = %{"result_type" => %{"aggregate" => "min", "field" => "view_count"}}
      {:ok, json, raw} = Execution.run(Post, action, arguments, exec_ctx)

      assert json == "10"
      assert raw == 10
    end

    test "executes read with aggregate sum", %{exec_ctx: exec_ctx} do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "Post 1", body: "Body", view_count: 10})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "Post 2", body: "Body", view_count: 25})
      |> Ash.create!()

      action = Ash.Resource.Info.action(Post, :read)
      arguments = %{"result_type" => %{"aggregate" => "sum", "field" => "view_count"}}
      {:ok, json, raw} = Execution.run(Post, action, arguments, exec_ctx)

      assert json == "35"
      assert raw == 35
    end

    test "executes read with aggregate count", %{exec_ctx: exec_ctx} do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "Post 1", body: "Body", view_count: 10})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "Post 2", body: "Body", view_count: 25})
      |> Ash.create!()

      action = Ash.Resource.Info.action(Post, :read)
      arguments = %{"result_type" => %{"aggregate" => "count", "field" => "view_count"}}
      {:ok, json, raw} = Execution.run(Post, action, arguments, exec_ctx)

      assert json == "2"
      assert raw == 2
    end
  end

  describe "run/4 with create actions" do
    test "executes create action with input", %{exec_ctx: exec_ctx} do
      action = Ash.Resource.Info.action(Post, :create)
      arguments = %{"input" => %{"title" => "New Post", "body" => "Content"}}
      {:ok, json, raw} = Execution.run(Post, action, arguments, exec_ctx)

      assert is_binary(json)
      decoded = Jason.decode!(json)
      assert decoded["title"] == "New Post"
      assert decoded["body"] == "Content"

      assert raw.title == "New Post"
      assert raw.body == "Content"
    end
  end

  describe "run/4 with update actions" do
    test "executes update action with identity filter (primary key)", %{exec_ctx: exec_ctx} do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "Original", body: "Body"})
        |> Ash.create!()

      action = Ash.Resource.Info.action(Post, :update)
      arguments = %{"id" => post.id, "input" => %{"title" => "Updated"}}
      {:ok, json, raw} = Execution.run(Post, action, arguments, exec_ctx)

      decoded = Jason.decode!(json)
      assert decoded["title"] == "Updated"
      assert raw.title == "Updated"
    end

    test "returns error when update target not found", %{exec_ctx: exec_ctx} do
      action = Ash.Resource.Info.action(Post, :update)
      arguments = %{"id" => Ash.UUID.generate(), "input" => %{"title" => "Updated"}}

      {:error, error_json} = Execution.run(Post, action, arguments, exec_ctx)

      assert is_binary(error_json)
      errors = Jason.decode!(error_json)
      assert is_list(errors)
    end
  end

  describe "run/4 with destroy actions" do
    test "executes destroy action with identity filter", %{exec_ctx: exec_ctx} do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "To Delete", body: "Body"})
        |> Ash.create!()

      action = Ash.Resource.Info.action(Post, :destroy)
      arguments = %{"id" => post.id}
      {:ok, json, raw} = Execution.run(Post, action, arguments, exec_ctx)

      assert is_binary(json)
      assert raw.id == post.id
    end

    test "returns error when destroy target not found", %{exec_ctx: exec_ctx} do
      action = Ash.Resource.Info.action(Post, :destroy)
      arguments = %{"id" => Ash.UUID.generate()}

      {:error, error_json} = Execution.run(Post, action, arguments, exec_ctx)

      assert is_binary(error_json)
      errors = Jason.decode!(error_json)
      assert is_list(errors)
    end
  end

  describe "run/4 with generic actions" do
    test "executes generic action with return value", %{exec_ctx: exec_ctx} do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "My Post", body: "Body"})
        |> Ash.create!()

      action = Ash.Resource.Info.action(Post, :get_title)
      arguments = %{"input" => %{"post_id" => post.id}}
      {:ok, json, raw} = Execution.run(Post, action, arguments, exec_ctx)

      assert json == "\"My Post\""
      assert raw == "My Post"
    end

    test "executes update action that returns updated record", %{exec_ctx: exec_ctx} do
      post =
        Post |> Ash.Changeset.for_create(:create, %{title: "Post", body: "Body"}) |> Ash.create!()

      action = Ash.Resource.Info.action(Post, :publish)
      arguments = %{"id" => post.id}
      {:ok, json, raw} = Execution.run(Post, action, arguments, exec_ctx)

      decoded = Jason.decode!(json)
      assert decoded["published"] == true
      assert raw.published == true
    end
  end

  describe "run/4 with load option" do
    test "loads relationships and calculations when specified", %{exec_ctx: exec_ctx} do
      _post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "Test Post", body: "Body"})
        |> Ash.create!()

      action = Ash.Resource.Info.action(Post, :read)
      exec_ctx_with_load = %{exec_ctx | load: [:title_length]}

      {:ok, json, _raw} = Execution.run(Post, action, %{}, exec_ctx_with_load)

      decoded = Jason.decode!(json)
      assert hd(decoded)["title_length"] == String.length("Test Post")
    end
  end

  describe "run/4 error handling" do
    test "returns JSON:API formatted errors on failure", %{exec_ctx: exec_ctx} do
      action = Ash.Resource.Info.action(Post, :create)
      # Missing required title
      arguments = %{"input" => %{}}

      {:error, error_json} = Execution.run(Post, action, arguments, exec_ctx)

      assert is_binary(error_json)
      errors = Jason.decode!(error_json)
      assert is_list(errors)
      assert length(errors) > 0

      error = hd(errors)
      assert error["code"]
      assert error["detail"]
    end
  end

  describe "nil argument normalization" do
    test "normalizes nil arguments to empty map", %{exec_ctx: exec_ctx} do
      action = Ash.Resource.Info.action(Post, :read)

      # Should not raise - nil arguments should be normalized
      {:ok, json, raw} = Execution.run(Post, action, nil, exec_ctx)

      assert is_binary(json)
      assert is_list(raw)
    end
  end
end
