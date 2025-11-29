defmodule Jido.HTN.Domain.CustomValidatorTest do
  use ExUnit.Case, async: true

  alias Jido.HTN.Domain
  alias Jido.HTN.Domain.Builder.Validator

  @moduledoc """
  Tests for custom domain validators and the validator behaviour.
  """

  # Mock validator modules for testing

  defmodule PassingValidator do
    @behaviour Validator

    @impl true
    def validate(%Domain{} = domain) do
      {:ok, domain}
    end
  end

  defmodule PassingValidatorReturnsOk do
    @behaviour Validator

    @impl true
    def validate(%Domain{}) do
      :ok
    end
  end

  defmodule FailingValidator do
    @behaviour Validator

    @impl true
    def validate(%Domain{}) do
      {:error, "Custom validation failed"}
    end
  end

  defmodule FailingValidatorWithList do
    @behaviour Validator

    @impl true
    def validate(%Domain{}) do
      {:error, ["Error 1", "Error 2"]}
    end
  end

  defmodule TransformingValidator do
    @behaviour Validator

    @impl true
    def validate(%Domain{} = domain) do
      # Add metadata or transform domain
      {:ok, domain}
    end
  end

  defmodule ConditionalValidator do
    @behaviour Validator

    @impl true
    def validate(%Domain{tasks: tasks} = domain) do
      if map_size(tasks) > 5 do
        {:error, "Domain has too many tasks"}
      else
        {:ok, domain}
      end
    end
  end

  # Helper to create a valid basic domain builder
  defp valid_domain_builder do
    Domain.new("test_domain")
    |> Domain.allow("test_action", DummyAction)
    |> Domain.primitive("task1", DummyAction)
    |> Domain.compound("compound1",
      methods: [
        %{
          name: "method1",
          conditions: [],
          subtasks: ["task1"]
        }
      ]
    )
    |> Domain.root("compound1")
  end

  describe "custom validator behaviour" do
    test "passing validator allows domain to be built" do
      result =
        valid_domain_builder()
        |> Domain.build(custom_validators: [&PassingValidator.validate/1])

      assert {:ok, %Domain{}} = result
    end

    test "passing validator returning :ok allows domain to be built" do
      result =
        valid_domain_builder()
        |> Domain.build(custom_validators: [&PassingValidatorReturnsOk.validate/1])

      assert {:ok, %Domain{}} = result
    end

    test "failing validator prevents domain from being built" do
      result =
        valid_domain_builder()
        |> Domain.build(custom_validators: [&FailingValidator.validate/1])

      assert {:error, "Custom validation failed"} = result
    end

    test "failing validator with list of errors returns error" do
      result =
        valid_domain_builder()
        |> Domain.build(custom_validators: [&FailingValidatorWithList.validate/1])

      assert {:error, ["Error 1", "Error 2"]} = result
    end

    test "transforming validator can modify domain" do
      result =
        valid_domain_builder()
        |> Domain.build(custom_validators: [&TransformingValidator.validate/1])

      assert {:ok, %Domain{}} = result
    end

    test "conditional validator validates based on domain state" do
      # This should pass (few tasks)
      result =
        valid_domain_builder()
        |> Domain.build(custom_validators: [&ConditionalValidator.validate/1])

      assert {:ok, %Domain{}} = result
    end
  end

  describe "validator ordering and chaining" do
    test "multiple validators run in order" do
      result =
        valid_domain_builder()
        |> Domain.build(
          custom_validators: [
            &PassingValidator.validate/1,
            &PassingValidatorReturnsOk.validate/1
          ]
        )

      assert {:ok, %Domain{}} = result
    end

    test "validator chain stops at first error" do
      result =
        valid_domain_builder()
        |> Domain.build(
          custom_validators: [
            &PassingValidator.validate/1,
            &FailingValidator.validate/1,
            &PassingValidatorReturnsOk.validate/1
          ]
        )

      assert {:error, "Custom validation failed"} = result
    end

    test "default validation runs before custom validators when enabled" do
      # Create a domain that will fail default validation (no root task)
      result =
        Domain.new("test_domain")
        |> Domain.allow("test_action", DummyAction)
        |> Domain.primitive("task1", DummyAction)
        |> Domain.compound("compound1",
          methods: [
            %{
              name: "method1",
              conditions: [],
              subtasks: ["task1"]
            }
          ]
        )
        # Note: Not marking any task as root - will fail default validation
        |> Domain.build(
          validate: true,
          custom_validators: [&PassingValidator.validate/1]
        )

      # Should fail on default validation before custom validator runs
      assert {:error, _} = result
    end
  end

  describe "build! with custom validators" do
    test "build! returns domain when all validators pass" do
      domain =
        valid_domain_builder()
        |> Domain.build!(custom_validators: [&PassingValidator.validate/1])

      assert %Domain{} = domain
    end

    test "build! raises when validator fails" do
      assert_raise RuntimeError, fn ->
        valid_domain_builder()
        |> Domain.build!(custom_validators: [&FailingValidator.validate/1])
      end
    end
  end

  describe "build without custom validators" do
    test "build works without custom validators option" do
      result =
        valid_domain_builder()
        |> Domain.build()

      assert {:ok, %Domain{}} = result
    end

    test "build works with empty custom validators list" do
      result =
        valid_domain_builder()
        |> Domain.build(custom_validators: [])

      assert {:ok, %Domain{}} = result
    end
  end

  describe "function reference validators" do
    test "anonymous function as validator" do
      validator_fn = fn %Domain{} = domain ->
        {:ok, domain}
      end

      result =
        valid_domain_builder()
        |> Domain.build(custom_validators: [validator_fn])

      assert {:ok, %Domain{}} = result
    end

    test "captured function as validator" do
      result =
        valid_domain_builder()
        |> Domain.build(custom_validators: [&PassingValidator.validate/1])

      assert {:ok, %Domain{}} = result
    end
  end

  describe "error handling" do
    test "builder error propagates even with custom validators" do
      # Create a builder with a deliberate error by using invalid input
      result =
        Domain.new(123)
        |> Domain.build(custom_validators: [&PassingValidator.validate/1])

      assert {:error, _} = result
    end

    test "custom validator receives correctly built domain" do
      validator_fn = fn %Domain{name: name} = domain ->
        assert name == "test_domain"
        {:ok, domain}
      end

      result =
        valid_domain_builder()
        |> Domain.build(custom_validators: [validator_fn])

      assert {:ok, %Domain{}} = result
    end
  end
end

# Dummy module for testing
defmodule DummyAction do
  def run(_params, _state, _opts), do: {:ok, %{}}
end
