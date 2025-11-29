# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Tool.SchemaTest do
  use ExUnit.Case, async: true

  alias AshAi.Tool.Schema

  defmodule Post do
    use Ash.Resource,
      domain: AshAi.Tool.SchemaTest.TestDomain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id

      attribute :title, :string do
        public? true
        allow_nil? false
      end

      attribute :body, :string do
        public? true
        allow_nil? true
      end

      attribute :view_count, :integer do
        public? true
        allow_nil? true
        default 0
      end

      attribute :secret, :string do
        public? false
        allow_nil? true
      end
    end

    aggregates do
      count :comment_count, :comments do
        public? true
      end
    end

    calculations do
      calculate :title_length, :integer, expr(string_length(title)) do
        public? true
      end
    end

    actions do
      defaults [:read, :destroy]

      create :create do
        primary? true
        accept [:title, :body, :view_count]

        argument :notify_subscribers, :boolean do
          allow_nil? false
        end
      end

      update :update do
        primary? true
        accept [:title, :body]
      end

      read :list do
        pagination do
          offset? true
          default_limit 50
          max_page_size 100
        end
      end

      action :archive, :string do
        argument :reason, :string do
          allow_nil? false
        end
      end
    end

    relationships do
      has_many :comments, AshAi.Tool.SchemaTest.Comment
    end
  end

  defmodule Comment do
    use Ash.Resource,
      domain: AshAi.Tool.SchemaTest.TestDomain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id

      attribute :content, :string do
        public? true
        allow_nil? false
      end
    end

    actions do
      defaults [:read, :create, :update, :destroy]
    end

    relationships do
      belongs_to :post, AshAi.Tool.SchemaTest.Post
    end
  end

  defmodule TestDomain do
    use Ash.Domain

    resources do
      resource Post
      resource Comment
    end
  end

  describe "for_read/4" do
    test "generates schema with all read parameters by default" do
      action = Ash.Resource.Info.action(Post, :read)
      schema = Schema.for_read(Post, action, nil)

      assert schema["type"] == "object"
      assert schema["additionalProperties"] == false

      properties = schema["properties"]
      assert Map.has_key?(properties, "filter")
      assert Map.has_key?(properties, "sort")
      assert Map.has_key?(properties, "limit")
      assert Map.has_key?(properties, "offset")
      assert Map.has_key?(properties, "result_type")

      assert properties["limit"]["default"] == 25
      assert properties["offset"]["default"] == 0
    end

    test "respects pagination settings" do
      action = Ash.Resource.Info.action(Post, :list)
      schema = Schema.for_read(Post, action, nil)

      assert schema["properties"]["limit"]["default"] == 50
    end

    test "filter includes public filterable fields" do
      action = Ash.Resource.Info.action(Post, :read)
      schema = Schema.for_read(Post, action, nil)

      filter_props = schema["properties"]["filter"]["properties"]
      assert Map.has_key?(filter_props, "title")
      assert Map.has_key?(filter_props, "body")
      assert Map.has_key?(filter_props, "view_count")
      refute Map.has_key?(filter_props, "secret")
    end

    test "sort includes public sortable fields" do
      action = Ash.Resource.Info.action(Post, :read)
      schema = Schema.for_read(Post, action, nil)

      sort_field_enum = schema["properties"]["sort"]["items"]["properties"]["field"]["enum"]
      assert "title" in sort_field_enum
      assert "body" in sort_field_enum
      assert "view_count" in sort_field_enum
      refute "secret" in sort_field_enum
    end

    test "result_type includes aggregate options" do
      action = Ash.Resource.Info.action(Post, :read)
      schema = Schema.for_read(Post, action, nil)

      result_type = schema["properties"]["result_type"]
      assert result_type["default"] == "run_query"
      assert length(result_type["oneOf"]) == 2

      [enum_option, aggregate_option] = result_type["oneOf"]
      assert "run_query" in enum_option["enum"]
      assert "count" in enum_option["enum"]
      assert "exists" in enum_option["enum"]

      assert aggregate_option["properties"]["aggregate"]["enum"] == [
               "max",
               "min",
               "sum",
               "avg",
               "count"
             ]

      assert "title" in aggregate_option["properties"]["field"]["enum"]
    end

    test "filters parameters when action_parameters is provided" do
      action = Ash.Resource.Info.action(Post, :read)
      schema = Schema.for_read(Post, action, nil, [:filter, :limit])

      properties = schema["properties"]
      assert Map.has_key?(properties, "filter")
      assert Map.has_key?(properties, "limit")
      refute Map.has_key?(properties, "sort")
      refute Map.has_key?(properties, "offset")
      refute Map.has_key?(properties, "result_type")
    end
  end

  describe "for_create/3" do
    test "generates schema with input object" do
      action = Ash.Resource.Info.action(Post, :create)
      schema = Schema.for_create(Post, action, nil)

      assert schema["type"] == "object"
      assert schema["additionalProperties"] == false
      assert schema["required"] == ["input"]

      input = schema["properties"]["input"]
      assert input["type"] == "object"

      input_props = input["properties"]
      assert Map.has_key?(input_props, "title")
      assert Map.has_key?(input_props, "body")
      assert Map.has_key?(input_props, "view_count")
      assert Map.has_key?(input_props, "notify_subscribers")
      refute Map.has_key?(input_props, "secret")
    end

    test "includes required attributes and arguments" do
      action = Ash.Resource.Info.action(Post, :create)
      schema = Schema.for_create(Post, action, nil)

      input_required = schema["properties"]["input"]["required"]
      assert "title" in input_required
      assert "notify_subscribers" in input_required
      refute "body" in input_required
    end
  end

  describe "for_update/3" do
    test "generates schema with input and identity keys" do
      action = Ash.Resource.Info.action(Post, :update)
      schema = Schema.for_update(Post, action, nil)

      assert schema["type"] == "object"
      assert schema["additionalProperties"] == false

      properties = schema["properties"]
      assert Map.has_key?(properties, "input")
      assert Map.has_key?(properties, "id")

      input_props = properties["input"]["properties"]
      assert Map.has_key?(input_props, "title")
      assert Map.has_key?(input_props, "body")
      refute Map.has_key?(input_props, "view_count")
    end

    test "primary key included as top-level property" do
      action = Ash.Resource.Info.action(Post, :update)
      schema = Schema.for_update(Post, action, nil)

      assert Map.has_key?(schema["properties"], "id")
      assert schema["properties"]["id"]["type"] == "string"
    end
  end

  describe "for_destroy/3" do
    test "generates schema with only identity keys" do
      action = Ash.Resource.Info.action(Post, :destroy)
      schema = Schema.for_destroy(Post, action, nil)

      assert schema["type"] == "object"
      assert schema["additionalProperties"] == false
      assert schema["required"] == []

      properties = schema["properties"]
      assert Map.has_key?(properties, "id")
      refute Map.has_key?(properties, "input")
    end
  end

  describe "for_generic/3" do
    test "generates schema with arguments only" do
      action = Ash.Resource.Info.action(Post, :archive)
      schema = Schema.for_generic(Post, action, nil)

      assert schema["type"] == "object"
      assert schema["additionalProperties"] == false
      assert schema["required"] == ["input"]

      input_props = schema["properties"]["input"]["properties"]
      assert Map.has_key?(input_props, "reason")
      refute Map.has_key?(input_props, "title")
    end

    test "handles actions with no arguments" do
      defmodule SimpleAction do
        use Ash.Resource,
          domain: AshAi.Tool.SchemaTest.SimpleDomain,
          data_layer: Ash.DataLayer.Ets

        ets do
          private? true
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :simple, :struct
        end
      end

      defmodule SimpleDomain do
        use Ash.Domain

        resources do
          resource SimpleAction
        end
      end

      action = Ash.Resource.Info.action(SimpleAction, :simple)
      schema = Schema.for_generic(SimpleAction, action, nil)

      assert schema["type"] == "object"
      assert schema["properties"] == %{}
      assert schema["required"] == []
    end
  end

  describe "for_action/4" do
    test "dispatches to for_read for read actions" do
      action = Ash.Resource.Info.action(Post, :read)
      schema = Schema.for_action(Post, action, nil)

      assert Map.has_key?(schema["properties"], "filter")
      assert Map.has_key?(schema["properties"], "sort")
    end

    test "dispatches to for_create for create actions" do
      action = Ash.Resource.Info.action(Post, :create)
      schema = Schema.for_action(Post, action, nil)

      assert Map.has_key?(schema["properties"], "input")
      refute Map.has_key?(schema["properties"], "filter")
    end

    test "dispatches to for_update for update actions" do
      action = Ash.Resource.Info.action(Post, :update)
      schema = Schema.for_action(Post, action, nil)

      assert Map.has_key?(schema["properties"], "input")
      assert Map.has_key?(schema["properties"], "id")
    end

    test "dispatches to for_destroy for destroy actions" do
      action = Ash.Resource.Info.action(Post, :destroy)
      schema = Schema.for_action(Post, action, nil)

      assert Map.has_key?(schema["properties"], "id")
      refute Map.has_key?(schema["properties"], "input")
    end

    test "dispatches to for_generic for generic actions" do
      action = Ash.Resource.Info.action(Post, :archive)
      schema = Schema.for_action(Post, action, nil)

      assert Map.has_key?(schema["properties"], "input")
      assert Map.has_key?(schema["properties"]["input"]["properties"], "reason")
    end

    test "passes action_parameters option to for_read" do
      action = Ash.Resource.Info.action(Post, :read)
      schema = Schema.for_action(Post, action, nil, action_parameters: [:filter, :limit])

      properties = schema["properties"]
      assert Map.has_key?(properties, "filter")
      assert Map.has_key?(properties, "limit")
      refute Map.has_key?(properties, "sort")
    end
  end
end
