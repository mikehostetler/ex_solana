# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAiTest do
  use ExUnit.Case, async: true
  alias __MODULE__.{Music, Artist, Album}

  @moduletag :capture_log

  defmodule Artist do
    use Ash.Resource, domain: Music, data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_v7_primary_key(:id, writable?: true)
      attribute(:name, :string, public?: true)
    end

    actions do
      default_accept([:*])
      defaults([:create, :read, :update, :destroy])

      action :say_hello, :string do
        description("Say hello")
        argument(:name, :string, allow_nil?: false)

        run(fn input, _ ->
          {:ok, "Hello, #{input.arguments.name}!"}
        end)
      end

      action :check_context, :map do
        description("Check if context is available")

        run(fn _input, context ->
          {:ok, %{context: context.source_context}}
        end)
      end
    end

    relationships do
      has_many(:albums, Album)
    end

    aggregates do
      count(:albums_count, :albums, public?: true, sortable?: false)

      sum(:albums_copies_sold, :albums, :copies_sold,
        default: 0,
        public?: true,
        filterable?: false
      )
    end
  end

  defmodule Album do
    use Ash.Resource, domain: Music, data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id, writable?: true)
      attribute(:title, :string)
      attribute(:copies_sold, :integer)
    end

    relationships do
      belongs_to(:artist, Artist)
    end

    actions do
      default_accept([:*])
      defaults([:create, :read, :update, :destroy])
    end
  end

  defmodule Music do
    use Ash.Domain, extensions: [AshAi]

    resources do
      resource(Artist)
      resource(Album)
    end

    @artist_load [:albums_count]
    tools do
      tool(:list_artists, Artist, :read, load: @artist_load, async: false)
      tool(:create_artist, Artist, :create, load: @artist_load, async: false)
      tool(:update_artist, Artist, :update, load: @artist_load, async: false)
      tool(:delete_artist, Artist, :destroy, load: @artist_load, async: false)
      tool(:say_hello, Artist, :say_hello, load: @artist_load, async: false)
      tool(:check_context, Artist, :check_context, async: false)
    end
  end

  describe "setup_ash_ai" do
    setup do
      artist =
        Artist
        |> Ash.Changeset.for_create(:create, %{name: "Chet Baker"})
        |> Ash.create!()

      %{artist: artist}
    end

    test "with read action", %{artist: artist} do
      tool_name = "list_artists"
      {tools, registry} = get_tools_and_registry()

      assert %ReqLLM.Tool{} = tool = tools |> Enum.find(&(&1.name == tool_name))

      assert tool.description == "Call the read action on the AshAiTest.Artist resource"

      assert tool.parameter_schema["additionalProperties"] == false

      assert tool.parameter_schema["properties"]["filter"] == %{
               "type" => "object",
               "description" => "Filter results",
               "properties" => %{
                 "id" => %{
                   "type" => "object",
                   "properties" => %{
                     "eq" => %{"format" => "uuid", "type" => "string"},
                     "greater_than" => %{"format" => "uuid", "type" => "string"},
                     "greater_than_or_equal" => %{
                       "format" => "uuid",
                       "type" => "string"
                     },
                     "in" => %{
                       "items" => %{"format" => "uuid", "type" => "string"},
                       "type" => "array"
                     },
                     "is_nil" => %{"type" => "boolean"},
                     "less_than" => %{"format" => "uuid", "type" => "string"},
                     "less_than_or_equal" => %{
                       "format" => "uuid",
                       "type" => "string"
                     },
                     "not_eq" => %{"format" => "uuid", "type" => "string"}
                   },
                   "additionalProperties" => false
                 },
                 "name" => %{
                   "type" => "object",
                   "properties" => %{
                     "contains" => %{"type" => "string"},
                     "eq" => %{"type" => "string"},
                     "greater_than" => %{"type" => "string"},
                     "greater_than_or_equal" => %{"type" => "string"},
                     "in" => %{"type" => "array", "items" => %{"type" => "string"}},
                     "is_nil" => %{"type" => "boolean"},
                     "less_than" => %{"type" => "string"},
                     "less_than_or_equal" => %{"type" => "string"},
                     "not_eq" => %{"type" => "string"}
                   },
                   "additionalProperties" => false
                 },
                 "albums_count" => %{
                   "type" => "object",
                   "additionalProperties" => false,
                   "properties" => %{
                     "eq" => %{"type" => "integer"},
                     "greater_than" => %{"type" => "integer"},
                     "greater_than_or_equal" => %{"type" => "integer"},
                     "in" => %{"items" => %{"type" => "integer"}, "type" => "array"},
                     "is_nil" => %{"type" => "boolean"},
                     "less_than" => %{"type" => "integer"},
                     "less_than_or_equal" => %{"type" => "integer"},
                     "not_eq" => %{"type" => "integer"}
                   }
                 }
               }
             }

      refute tool.parameter_schema["properties"]["input"]

      assert tool.parameter_schema["properties"]["limit"] == %{
               "type" => "integer",
               "description" => "The maximum number of records to return",
               "default" => 25
             }

      assert tool.parameter_schema["properties"]["offset"] == %{
               "type" => "integer",
               "description" => "The number of records to skip",
               "default" => 0
             }

      assert tool.parameter_schema["properties"]["sort"] == %{
               "type" => "array",
               "items" => %{
                 "type" => "object",
                 "properties" => %{
                   "direction" => %{
                     "type" => "string",
                     "description" => "The direction to sort by",
                     "enum" => ["asc", "desc"]
                   },
                   "field" => %{
                     "type" => "string",
                     "description" => "The field to sort by",
                     "enum" => ["id", "name", "albums_copies_sold"]
                   }
                 }
               }
             }

      # Call the tool directly
      callback = Map.fetch!(registry, tool_name)

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{}
      }

      assert {:ok, _text, raw} =
               callback.(%{"filter" => %{"name" => %{"eq" => artist.name}}}, context)

      assert [fetched_artist] = raw
      assert fetched_artist.id == artist.id
      assert fetched_artist.albums_count == 0
      assert %Ash.NotLoaded{} = fetched_artist.albums_copies_sold
    end

    test "with create action" do
      tool_name = "create_artist"
      {tools, registry} = get_tools_and_registry()

      assert %ReqLLM.Tool{} = tool = tools |> Enum.find(&(&1.name == tool_name))

      assert tool.description == "Call the create action on the AshAiTest.Artist resource"

      assert tool.parameter_schema["additionalProperties"] == false

      assert tool.parameter_schema["properties"]["input"] == %{
               "type" => "object",
               "properties" => %{
                 "id" => %{"type" => "string", "format" => "uuid"},
                 "name" => %{"type" => "string"}
               },
               "required" => []
             }

      # Call the tool directly
      callback = Map.fetch!(registry, tool_name)

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{}
      }

      assert {:ok, _text, created_artist} =
               callback.(%{"input" => %{"name" => "Chat Faker"}}, context)

      assert created_artist.name == "Chat Faker"
      assert created_artist.albums_count == 0
      assert %Ash.NotLoaded{} = created_artist.albums_copies_sold
    end

    test "with update action", %{artist: artist} do
      tool_name = "update_artist"
      {tools, registry} = get_tools_and_registry()

      assert %ReqLLM.Tool{} = tool = tools |> Enum.find(&(&1.name == tool_name))

      assert tool.description == "Call the update action on the AshAiTest.Artist resource"

      assert tool.parameter_schema["additionalProperties"] == false

      assert tool.parameter_schema["properties"]["id"] == %{
               "type" => "string",
               "format" => "uuid"
             }

      assert tool.parameter_schema["properties"]["input"] == %{
               "type" => "object",
               "properties" => %{
                 "id" => %{"type" => "string", "format" => "uuid"},
                 "name" => %{"type" => "string"}
               },
               "required" => []
             }

      # Call the tool directly
      callback = Map.fetch!(registry, tool_name)

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{}
      }

      assert {:ok, _text, updated_artist} =
               callback.(%{"id" => artist.id, "input" => %{"name" => "Chat Faker"}}, context)

      assert updated_artist.id == artist.id
      assert updated_artist.name == "Chat Faker"
      assert updated_artist.albums_count == 0
      assert %Ash.NotLoaded{} = updated_artist.albums_copies_sold
    end

    test "with destroy action", %{artist: artist} do
      tool_name = "delete_artist"
      {tools, registry} = get_tools_and_registry()

      assert %ReqLLM.Tool{} = tool = tools |> Enum.find(&(&1.name == tool_name))

      assert tool.description == "Call the destroy action on the AshAiTest.Artist resource"

      assert tool.parameter_schema["additionalProperties"] == false

      assert tool.parameter_schema["properties"]["id"] == %{
               "type" => "string",
               "format" => "uuid"
             }

      # no input schema because no inputs
      refute tool.parameter_schema["properties"]["input"]

      # Call the tool directly
      callback = Map.fetch!(registry, tool_name)

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{}
      }

      assert {:ok, _text, destroyed_artist} = callback.(%{"id" => artist.id}, context)

      assert destroyed_artist.id == artist.id
      assert destroyed_artist.name == "Chet Baker"
      assert %Ash.NotLoaded{} = destroyed_artist.albums_copies_sold
    end

    test "with generic action" do
      tool_name = "say_hello"
      {tools, registry} = get_tools_and_registry()

      assert %ReqLLM.Tool{} = tool = tools |> Enum.find(&(&1.name == tool_name))

      assert tool.description == "Say hello"

      assert tool.parameter_schema["additionalProperties"] == false

      assert tool.parameter_schema["properties"]["input"] == %{
               "type" => "object",
               "properties" => %{"name" => %{"type" => "string"}},
               "required" => ["name"]
             }

      # Call the tool directly
      callback = Map.fetch!(registry, tool_name)

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{}
      }

      assert {:ok, _text, result} = callback.(%{"input" => %{"name" => "Chat Faker"}}, context)

      assert "Hello, Chat Faker!" = result
    end

    test "context is accessible in tool execution" do
      custom_context = %{shared: %{conversation_id: "test-123", user_id: 42}}

      {_tools, registry} = get_tools_and_registry()

      callback = Map.fetch!(registry, "check_context")

      context = %{
        actor: nil,
        tenant: nil,
        context: custom_context,
        tool_callbacks: %{}
      }

      assert {:ok, _text, result} = callback.(%{}, context)

      assert result.context.shared == custom_context.shared
      assert result.context.conversation_id == "test-123"
      assert result.context.user_id == 42
    end
  end

  defp get_tools_and_registry do
    opts = [otp_app: :ash_ai, actions: [{Artist, :*}]]

    # Get exposed tools
    tool_defs = AshAi.exposed_tools(opts)

    # Convert to {tool, callback} tuples
    tool_tuples = Enum.map(tool_defs, &AshAi.tool/1)

    # Separate tools and callbacks
    {tools, callbacks} = Enum.unzip(tool_tuples)

    # Build registry mapping tool name to callback function (function/2)
    registry =
      Enum.zip(tools, callbacks)
      |> Enum.into(%{}, fn {tool, callback} -> {tool.name, callback} end)

    {tools, registry}
  end
end
