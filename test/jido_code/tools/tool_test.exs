defmodule JidoCode.Tools.ToolTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.{Param, Tool}

  # Mock handler module for testing
  defmodule MockHandler do
    def execute(_params, _context), do: {:ok, "result"}
  end

  describe "new/1" do
    test "creates tool with required fields" do
      assert {:ok, tool} =
               Tool.new(%{
                 name: "read_file",
                 description: "Read a file",
                 handler: MockHandler
               })

      assert tool.name == "read_file"
      assert tool.description == "Read a file"
      assert tool.handler == MockHandler
      assert tool.parameters == []
    end

    test "creates tool with parameters" do
      assert {:ok, tool} =
               Tool.new(%{
                 name: "write_file",
                 description: "Write to a file",
                 handler: MockHandler,
                 parameters: [
                   %{name: "path", type: :string, description: "File path"},
                   %{name: "content", type: :string, description: "File content"}
                 ]
               })

      assert length(tool.parameters) == 2
      assert Enum.at(tool.parameters, 0).name == "path"
      assert Enum.at(tool.parameters, 1).name == "content"
    end

    test "accepts Param structs directly" do
      param = %Param{name: "path", type: :string, description: "File path", required: true}

      assert {:ok, tool} =
               Tool.new(%{
                 name: "read_file",
                 description: "Read a file",
                 handler: MockHandler,
                 parameters: [param]
               })

      assert tool.parameters == [param]
    end

    test "converts atom name to string" do
      assert {:ok, tool} =
               Tool.new(%{
                 name: :read_file,
                 description: "Read a file",
                 handler: MockHandler
               })

      assert tool.name == "read_file"
    end

    test "validates name format - must start with lowercase" do
      assert {:error, msg} =
               Tool.new(%{
                 name: "ReadFile",
                 description: "Read a file",
                 handler: MockHandler
               })

      assert msg =~ "must start with lowercase letter"
    end

    test "validates name format - no special characters" do
      assert {:error, msg} =
               Tool.new(%{
                 name: "read-file",
                 description: "Read a file",
                 handler: MockHandler
               })

      assert msg =~ "lowercase letters, numbers, and underscores"
    end

    test "allows underscores in name" do
      assert {:ok, tool} =
               Tool.new(%{
                 name: "read_file_contents",
                 description: "Read a file",
                 handler: MockHandler
               })

      assert tool.name == "read_file_contents"
    end

    test "allows numbers in name" do
      assert {:ok, tool} =
               Tool.new(%{
                 name: "read_file_v2",
                 description: "Read a file",
                 handler: MockHandler
               })

      assert tool.name == "read_file_v2"
    end

    test "returns error for missing name" do
      assert {:error, "name is required"} =
               Tool.new(%{
                 description: "Read a file",
                 handler: MockHandler
               })
    end

    test "returns error for empty name" do
      assert {:error, "name must be a non-empty string"} =
               Tool.new(%{
                 name: "",
                 description: "Read a file",
                 handler: MockHandler
               })
    end

    test "returns error for missing description" do
      assert {:error, "description is required"} =
               Tool.new(%{
                 name: "read_file",
                 handler: MockHandler
               })
    end

    test "returns error for empty description" do
      assert {:error, "description must be a non-empty string"} =
               Tool.new(%{
                 name: "read_file",
                 description: "",
                 handler: MockHandler
               })
    end

    test "returns error for missing handler" do
      assert {:error, "handler is required"} =
               Tool.new(%{
                 name: "read_file",
                 description: "Read a file"
               })
    end

    test "returns error for invalid handler" do
      assert {:error, "handler must be a module atom"} =
               Tool.new(%{
                 name: "read_file",
                 description: "Read a file",
                 handler: "not_a_module"
               })
    end

    test "returns error for invalid parameter" do
      assert {:error, msg} =
               Tool.new(%{
                 name: "read_file",
                 description: "Read a file",
                 handler: MockHandler,
                 parameters: [%{name: "bad"}]
               })

      assert msg =~ "invalid parameter"
    end
  end

  describe "new!/1" do
    test "returns tool on success" do
      tool =
        Tool.new!(%{
          name: "read_file",
          description: "Read a file",
          handler: MockHandler
        })

      assert %Tool{} = tool
    end

    test "raises on validation failure" do
      assert_raise ArgumentError, ~r/handler is required/, fn ->
        Tool.new!(%{name: "read_file", description: "Bad"})
      end
    end
  end

  describe "to_llm_function/1" do
    test "converts tool without parameters" do
      tool = %Tool{
        name: "list_files",
        description: "List all files",
        handler: MockHandler,
        parameters: []
      }

      result = Tool.to_llm_function(tool)

      assert result == %{
               type: "function",
               function: %{
                 name: "list_files",
                 description: "List all files",
                 parameters: %{
                   type: "object",
                   properties: %{},
                   required: []
                 }
               }
             }
    end

    test "converts tool with parameters" do
      {:ok, tool} =
        Tool.new(%{
          name: "read_file",
          description: "Read file contents",
          handler: MockHandler,
          parameters: [
            %{name: "path", type: :string, description: "File path to read", required: true},
            %{
              name: "encoding",
              type: :string,
              description: "File encoding",
              required: false,
              default: "utf-8"
            }
          ]
        })

      result = Tool.to_llm_function(tool)

      assert result.type == "function"
      assert result.function.name == "read_file"
      assert result.function.description == "Read file contents"

      params = result.function.parameters
      assert params.type == "object"
      assert params.required == ["path"]
      assert params.properties["path"] == %{type: "string", description: "File path to read"}

      assert params.properties["encoding"] == %{
               type: "string",
               description: "File encoding",
               default: "utf-8"
             }
    end

    test "includes all parameter types in schema" do
      {:ok, tool} =
        Tool.new(%{
          name: "complex_tool",
          description: "A complex tool",
          handler: MockHandler,
          parameters: [
            %{name: "text", type: :string, description: "Text input"},
            %{name: "count", type: :integer, description: "Count"},
            %{name: "enabled", type: :boolean, description: "Enable flag"},
            %{name: "items", type: :array, description: "List of items", items: :string},
            %{
              name: "config",
              type: :object,
              description: "Configuration",
              properties: [
                %{name: "timeout", type: :integer, description: "Timeout"}
              ]
            }
          ]
        })

      result = Tool.to_llm_function(tool)
      props = result.function.parameters.properties

      assert props["text"].type == "string"
      assert props["count"].type == "integer"
      assert props["enabled"].type == "boolean"
      assert props["items"].type == "array"
      assert props["config"].type == "object"
    end
  end

  describe "required_params/1" do
    test "returns names of required parameters" do
      {:ok, tool} =
        Tool.new(%{
          name: "test_tool",
          description: "Test tool",
          handler: MockHandler,
          parameters: [
            %{name: "required1", type: :string, description: "Required", required: true},
            %{name: "optional", type: :string, description: "Optional", required: false},
            %{name: "required2", type: :integer, description: "Required", required: true}
          ]
        })

      assert Tool.required_params(tool) == ["required1", "required2"]
    end

    test "returns empty list when no required params" do
      {:ok, tool} =
        Tool.new(%{
          name: "test_tool",
          description: "Test tool",
          handler: MockHandler,
          parameters: [
            %{name: "optional", type: :string, description: "Optional", required: false}
          ]
        })

      assert Tool.required_params(tool) == []
    end
  end

  describe "validate_args/2" do
    setup do
      {:ok, tool} =
        Tool.new(%{
          name: "test_tool",
          description: "Test tool",
          handler: MockHandler,
          parameters: [
            %{name: "path", type: :string, description: "Path", required: true},
            %{name: "count", type: :integer, description: "Count", required: false},
            %{name: "enabled", type: :boolean, description: "Enabled", required: false}
          ]
        })

      %{tool: tool}
    end

    test "returns ok for valid args", %{tool: tool} do
      assert :ok = Tool.validate_args(tool, %{"path" => "/tmp/file"})
    end

    test "returns ok for all valid args", %{tool: tool} do
      assert :ok = Tool.validate_args(tool, %{"path" => "/tmp", "count" => 10, "enabled" => true})
    end

    test "returns error for missing required param", %{tool: tool} do
      assert {:error, "missing required parameter: path"} = Tool.validate_args(tool, %{})
    end

    test "returns error for multiple missing required params" do
      {:ok, tool} =
        Tool.new(%{
          name: "test_tool",
          description: "Test",
          handler: MockHandler,
          parameters: [
            %{name: "a", type: :string, description: "A", required: true},
            %{name: "b", type: :string, description: "B", required: true}
          ]
        })

      assert {:error, msg} = Tool.validate_args(tool, %{})
      assert msg =~ "missing required parameters"
      assert msg =~ "a"
      assert msg =~ "b"
    end

    test "returns error for unknown param", %{tool: tool} do
      assert {:error, "unknown parameter: foo"} =
               Tool.validate_args(tool, %{"path" => "/tmp", "foo" => "bar"})
    end

    test "returns error for wrong type - string", %{tool: tool} do
      assert {:error, msg} = Tool.validate_args(tool, %{"path" => 123})
      assert msg =~ "parameter 'path' must be a string"
    end

    test "returns error for wrong type - integer", %{tool: tool} do
      assert {:error, msg} = Tool.validate_args(tool, %{"path" => "/tmp", "count" => "ten"})
      assert msg =~ "parameter 'count' must be an integer"
    end

    test "returns error for wrong type - boolean", %{tool: tool} do
      assert {:error, msg} = Tool.validate_args(tool, %{"path" => "/tmp", "enabled" => "yes"})
      assert msg =~ "parameter 'enabled' must be a boolean"
    end

    test "validates array type" do
      {:ok, tool} =
        Tool.new(%{
          name: "test_tool",
          description: "Test",
          handler: MockHandler,
          parameters: [
            %{name: "items", type: :array, description: "Items", required: true}
          ]
        })

      assert :ok = Tool.validate_args(tool, %{"items" => [1, 2, 3]})
      assert {:error, msg} = Tool.validate_args(tool, %{"items" => "not array"})
      assert msg =~ "must be an array"
    end

    test "validates object type" do
      {:ok, tool} =
        Tool.new(%{
          name: "test_tool",
          description: "Test",
          handler: MockHandler,
          parameters: [
            %{name: "config", type: :object, description: "Config", required: true}
          ]
        })

      assert :ok = Tool.validate_args(tool, %{"config" => %{"key" => "value"}})
      assert {:error, msg} = Tool.validate_args(tool, %{"config" => "not object"})
      assert msg =~ "must be an object"
    end

    test "validates number type accepts integers and floats" do
      {:ok, tool} =
        Tool.new(%{
          name: "test_tool",
          description: "Test",
          handler: MockHandler,
          parameters: [
            %{name: "value", type: :number, description: "Value", required: true}
          ]
        })

      assert :ok = Tool.validate_args(tool, %{"value" => 42})
      assert :ok = Tool.validate_args(tool, %{"value" => 3.14})
      assert {:error, msg} = Tool.validate_args(tool, %{"value" => "not number"})
      assert msg =~ "must be a number"
    end
  end
end
