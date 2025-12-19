defmodule JidoCode.Tools.ParamTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Param

  describe "new/1" do
    test "creates param with required fields" do
      assert {:ok, param} =
               Param.new(%{
                 name: "path",
                 type: :string,
                 description: "The file path"
               })

      assert param.name == "path"
      assert param.type == :string
      assert param.description == "The file path"
      assert param.required == true
      assert param.default == nil
    end

    test "creates param with all fields" do
      assert {:ok, param} =
               Param.new(%{
                 name: "recursive",
                 type: :boolean,
                 description: "Search recursively",
                 required: false,
                 default: false
               })

      assert param.name == "recursive"
      assert param.type == :boolean
      assert param.description == "Search recursively"
      assert param.required == false
      assert param.default == false
    end

    test "converts atom name to string" do
      assert {:ok, param} =
               Param.new(%{
                 name: :path,
                 type: :string,
                 description: "File path"
               })

      assert param.name == "path"
    end

    test "validates all supported types" do
      for type <- [:string, :integer, :number, :boolean, :array, :object] do
        assert {:ok, param} =
                 Param.new(%{
                   name: "test",
                   type: type,
                   description: "Test param"
                 })

        assert param.type == type
      end
    end

    test "returns error for invalid type" do
      assert {:error, msg} =
               Param.new(%{
                 name: "test",
                 type: :invalid,
                 description: "Test"
               })

      assert msg =~ "invalid type :invalid"
      assert msg =~ "string, integer, number, boolean, array, object"
    end

    test "returns error for missing name" do
      assert {:error, "name is required"} =
               Param.new(%{
                 type: :string,
                 description: "Test"
               })
    end

    test "returns error for empty name" do
      assert {:error, "name must be a non-empty string"} =
               Param.new(%{
                 name: "",
                 type: :string,
                 description: "Test"
               })
    end

    test "returns error for missing type" do
      assert {:error, "type is required"} =
               Param.new(%{
                 name: "test",
                 description: "Test"
               })
    end

    test "returns error for missing description" do
      assert {:error, "description is required"} =
               Param.new(%{
                 name: "test",
                 type: :string
               })
    end

    test "returns error for empty description" do
      assert {:error, "description must be a non-empty string"} =
               Param.new(%{
                 name: "test",
                 type: :string,
                 description: ""
               })
    end

    test "creates array param with items type" do
      assert {:ok, param} =
               Param.new(%{
                 name: "patterns",
                 type: :array,
                 description: "List of patterns",
                 items: :string
               })

      assert param.type == :array
      assert param.items == :string
    end

    test "defaults array items to string" do
      assert {:ok, param} =
               Param.new(%{
                 name: "values",
                 type: :array,
                 description: "List of values"
               })

      assert param.items == :string
    end

    test "creates object param with properties" do
      assert {:ok, param} =
               Param.new(%{
                 name: "options",
                 type: :object,
                 description: "Configuration options",
                 properties: [
                   %{name: "timeout", type: :integer, description: "Timeout in ms"},
                   %{name: "verbose", type: :boolean, description: "Enable verbose output"}
                 ]
               })

      assert param.type == :object
      assert length(param.properties) == 2
      assert Enum.at(param.properties, 0).name == "timeout"
      assert Enum.at(param.properties, 1).name == "verbose"
    end

    test "creates param with enum constraint" do
      assert {:ok, param} =
               Param.new(%{
                 name: "format",
                 type: :string,
                 description: "Output format",
                 enum: ["json", "text", "xml"]
               })

      assert param.enum == ["json", "text", "xml"]
    end
  end

  describe "new!/1" do
    test "returns param on success" do
      param =
        Param.new!(%{
          name: "test",
          type: :string,
          description: "Test param"
        })

      assert %Param{} = param
    end

    test "raises on validation failure" do
      assert_raise ArgumentError, ~r/type is required/, fn ->
        Param.new!(%{name: "test", description: "Bad"})
      end
    end
  end

  describe "to_json_schema/1" do
    test "converts simple string param" do
      param = %Param{
        name: "path",
        type: :string,
        description: "File path",
        required: true
      }

      schema = Param.to_json_schema(param)

      assert schema == %{
               type: "string",
               description: "File path"
             }
    end

    test "converts integer param" do
      param = %Param{
        name: "count",
        type: :integer,
        description: "Number of items",
        required: true
      }

      schema = Param.to_json_schema(param)
      assert schema.type == "integer"
    end

    test "converts boolean param" do
      param = %Param{
        name: "enabled",
        type: :boolean,
        description: "Enable feature",
        required: false
      }

      schema = Param.to_json_schema(param)
      assert schema.type == "boolean"
    end

    test "converts array param with items" do
      param = %Param{
        name: "files",
        type: :array,
        description: "List of files",
        required: true,
        items: :string
      }

      schema = Param.to_json_schema(param)

      assert schema == %{
               type: "array",
               description: "List of files",
               items: %{type: "string"}
             }
    end

    test "converts object param with properties" do
      {:ok, param} =
        Param.new(%{
          name: "config",
          type: :object,
          description: "Configuration",
          properties: [
            %{name: "timeout", type: :integer, description: "Timeout", required: true},
            %{name: "retry", type: :boolean, description: "Retry", required: false}
          ]
        })

      schema = Param.to_json_schema(param)

      assert schema.type == "object"
      assert schema.description == "Configuration"
      assert schema.properties["timeout"] == %{type: "integer", description: "Timeout"}
      assert schema.properties["retry"] == %{type: "boolean", description: "Retry"}
      assert schema.required == ["timeout"]
    end

    test "includes enum constraint" do
      param = %Param{
        name: "level",
        type: :string,
        description: "Log level",
        required: true,
        enum: ["debug", "info", "warn", "error"]
      }

      schema = Param.to_json_schema(param)

      assert schema.enum == ["debug", "info", "warn", "error"]
    end

    test "includes default value" do
      param = %Param{
        name: "timeout",
        type: :integer,
        description: "Timeout in ms",
        required: false,
        default: 30_000
      }

      schema = Param.to_json_schema(param)

      assert schema.default == 30_000
    end
  end
end
