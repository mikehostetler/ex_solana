defmodule JidoCode.Tools.Definitions.ShellTest do
  use ExUnit.Case, async: false

  alias JidoCode.Tools.{Executor, Registry, Result}

  alias JidoCode.Tools.Definitions.Shell, as: Definitions

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    # Clear and set up registry for each test
    Registry.clear()

    # Register all shell tools
    for tool <- Definitions.all() do
      :ok = Registry.register(tool)
    end

    {:ok, project_root: tmp_dir}
  end

  describe "all/0" do
    test "returns shell tools" do
      tools = Definitions.all()
      assert length(tools) == 1

      names = Enum.map(tools, & &1.name)
      assert "run_command" in names
    end
  end

  describe "tool definitions" do
    test "run_command has correct schema" do
      tool = Definitions.run_command()
      assert tool.name == "run_command"
      assert tool.description =~ "Execute"
      assert tool.description =~ "stderr merged"
      assert tool.description =~ "allowed commands"
      assert length(tool.parameters) == 3

      command_param = Enum.find(tool.parameters, &(&1.name == "command"))
      args_param = Enum.find(tool.parameters, &(&1.name == "args"))
      timeout_param = Enum.find(tool.parameters, &(&1.name == "timeout"))

      assert command_param.required == true
      assert command_param.description =~ "allowlist"
      assert args_param.required == false
      assert args_param.description =~ "traversal"
      assert timeout_param.required == false
      assert timeout_param.description =~ "25000"
    end
  end

  describe "executor integration" do
    test "run_command tool works via executor", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "run_command",
        arguments: %{"command" => "echo", "args" => ["hello"]}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      output = Jason.decode!(result.content)
      assert output["exit_code"] == 0
      assert String.trim(output["stdout"]) == "hello"
    end

    test "handles command failure", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "run_command",
        arguments: %{"command" => "false"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      output = Jason.decode!(result.content)
      assert output["exit_code"] != 0
    end

    test "executor validates arguments", %{project_root: project_root} do
      # Missing required argument
      tool_call = %{
        id: "call_123",
        name: "run_command",
        arguments: %{}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "missing required parameter"
    end

    test "executor rejects unknown parameters", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "run_command",
        arguments: %{"command" => "echo", "unknown_param" => "value"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "unknown parameter"
    end

    test "results can be converted to LLM messages", %{project_root: project_root} do
      tool_call = %{
        id: "call_abc",
        name: "run_command",
        arguments: %{"command" => "true"}
      }

      context = %{project_root: project_root}
      {:ok, result} = Executor.execute(tool_call, context: context)

      message = Result.to_llm_message(result)
      assert message.role == "tool"
      assert message.tool_call_id == "call_abc"
      assert is_binary(message.content)
    end

    test "runs commands in project directory", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "run_command",
        arguments: %{"command" => "pwd"}
      }

      context = %{project_root: project_root}
      {:ok, result} = Executor.execute(tool_call, context: context)

      output = Jason.decode!(result.content)
      assert String.contains?(output["stdout"], project_root)
    end
  end

  describe "security via executor" do
    test "blocks shell interpreters", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "run_command",
        arguments: %{"command" => "bash", "args" => ["-c", "echo test"]}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "Shell interpreters are blocked"
    end

    test "blocks unknown commands", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "run_command",
        arguments: %{"command" => "evil_command"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "not allowed"
    end

    test "blocks path traversal in arguments", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "run_command",
        arguments: %{"command" => "cat", "args" => ["../../../etc/passwd"]}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "Path traversal not allowed"
    end
  end

  describe "batch execution" do
    test "executes multiple commands in batch", %{project_root: project_root} do
      tool_calls = [
        %{
          id: "call_1",
          name: "run_command",
          arguments: %{"command" => "echo", "args" => ["first"]}
        },
        %{
          id: "call_2",
          name: "run_command",
          arguments: %{"command" => "echo", "args" => ["second"]}
        },
        %{
          id: "call_3",
          name: "run_command",
          arguments: %{"command" => "true"}
        }
      ]

      context = %{project_root: project_root}
      {:ok, results} = Executor.execute_batch(tool_calls, context: context)

      assert length(results) == 3
      assert Enum.all?(results, &(&1.status == :ok))

      [first, second, third] = results
      assert String.contains?(Jason.decode!(first.content)["stdout"], "first")
      assert String.contains?(Jason.decode!(second.content)["stdout"], "second")
      assert Jason.decode!(third.content)["exit_code"] == 0
    end

    test "batch handles mixed success and failure", %{project_root: project_root} do
      tool_calls = [
        %{
          id: "call_1",
          name: "run_command",
          arguments: %{"command" => "echo", "args" => ["success"]}
        },
        %{
          id: "call_2",
          name: "run_command",
          arguments: %{"command" => "bash"}
        },
        %{
          id: "call_3",
          name: "run_command",
          arguments: %{"command" => "true"}
        }
      ]

      context = %{project_root: project_root}
      {:ok, results} = Executor.execute_batch(tool_calls, context: context)

      assert length(results) == 3

      [first, second, third] = results
      assert first.status == :ok
      assert second.status == :error
      assert second.content =~ "Shell interpreters are blocked"
      assert third.status == :ok
    end
  end
end
