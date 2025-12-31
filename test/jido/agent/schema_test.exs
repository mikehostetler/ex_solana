defmodule JidoTest.Agent.SchemaTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Schema

  describe "merge_with_skills/2" do
    test "nil base with no skills returns nil" do
      assert Schema.merge_with_skills(nil, []) == nil
    end

    test "base schema with no skills returns base" do
      base = Zoi.object(%{mode: Zoi.atom()})
      result = Schema.merge_with_skills(base, [])
      assert result == base
    end

    test "nil base with skills returns skill fields only" do
      skill_spec = %Jido.Skill.Spec{
        module: MySkill,
        name: "my_skill",
        state_key: :my_skill,
        schema: Zoi.object(%{count: Zoi.integer()}),
        actions: [],
        config: %{}
      }

      result = Schema.merge_with_skills(nil, [skill_spec])

      assert result != nil
      keys = Schema.known_keys(result)
      assert :my_skill in keys
    end

    test "base with skills merges both" do
      base = Zoi.object(%{mode: Zoi.atom()})

      skill_spec = %Jido.Skill.Spec{
        module: MySkill,
        name: "my_skill",
        state_key: :skill_data,
        schema: Zoi.object(%{value: Zoi.integer()}),
        actions: [],
        config: %{}
      }

      result = Schema.merge_with_skills(base, [skill_spec])

      keys = Schema.known_keys(result)
      assert :mode in keys
      assert :skill_data in keys
    end

    test "filters out skills without schema" do
      skill_with_schema = %Jido.Skill.Spec{
        module: SkillA,
        name: "skill_a",
        state_key: :skill_a,
        schema: Zoi.object(%{a: Zoi.integer()}),
        actions: [],
        config: %{}
      }

      skill_without_schema = %Jido.Skill.Spec{
        module: SkillB,
        name: "skill_b",
        state_key: :skill_b,
        schema: nil,
        actions: [],
        config: %{}
      }

      result = Schema.merge_with_skills(nil, [skill_with_schema, skill_without_schema])

      keys = Schema.known_keys(result)
      assert :skill_a in keys
      refute :skill_b in keys
    end
  end

  describe "known_keys/1" do
    test "returns empty list for nil" do
      assert Schema.known_keys(nil) == []
    end

    test "returns keys from Zoi object with map fields" do
      schema = Zoi.object(%{status: Zoi.atom(), count: Zoi.integer()})
      keys = Schema.known_keys(schema)
      assert :status in keys
      assert :count in keys
    end

    test "returns empty list for unknown schema type" do
      assert Schema.known_keys("not a schema") == []
      assert Schema.known_keys(123) == []
    end
  end

  describe "defaults_from_zoi_schema/1" do
    test "returns empty map for nil" do
      assert Schema.defaults_from_zoi_schema(nil) == %{}
    end

    test "extracts defaults from Zoi object" do
      schema =
        Zoi.object(%{
          status: Zoi.atom() |> Zoi.default(:idle),
          count: Zoi.integer()
        })

      defaults = Schema.defaults_from_zoi_schema(schema)
      assert defaults == %{status: :idle}
    end

    test "handles multiple defaults" do
      schema =
        Zoi.object(%{
          status: Zoi.atom() |> Zoi.default(:idle),
          count: Zoi.integer() |> Zoi.default(0),
          name: Zoi.string()
        })

      defaults = Schema.defaults_from_zoi_schema(schema)
      assert defaults == %{status: :idle, count: 0}
    end

    test "returns empty map when no defaults" do
      schema =
        Zoi.object(%{
          status: Zoi.atom(),
          count: Zoi.integer()
        })

      defaults = Schema.defaults_from_zoi_schema(schema)
      assert defaults == %{}
    end

    test "returns empty map for unknown schema type" do
      assert Schema.defaults_from_zoi_schema("not a schema") == %{}
    end
  end
end
