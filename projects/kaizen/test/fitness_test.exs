defmodule Kaizen.FitnessTest do
  use ExUnit.Case
  doctest Kaizen.Fitness

  defmodule SimpleFitness do
    use Kaizen.Fitness

    def evaluate(number, _context) when is_number(number) do
      {:ok, number * 1.0}
    end

    def evaluate(_entity, _context) do
      {:error, :invalid_entity}
    end
  end

  defmodule MetadataFitness do
    use Kaizen.Fitness

    def evaluate(string, _context) when is_binary(string) do
      score = String.length(string) / 10.0
      {:ok, %{score: score, metadata: %{length: String.length(string)}}}
    end
  end

  defmodule MixedFitness do
    use Kaizen.Fitness

    def evaluate(entity, context) do
      case entity do
        n when is_number(n) -> {:ok, n * 1.0}
        s when is_binary(s) -> {:ok, %{score: String.length(s) / 10.0}}
        _ -> Map.get(context, :default, {:error, :invalid})
      end
    end
  end

  defmodule InvalidFitness do
    use Kaizen.Fitness

    def evaluate(_entity, %{return: return_value}) do
      return_value
    end

    def evaluate(_entity, _context) do
      nil
    end
  end

  describe "batch_evaluate default implementation with simple scores" do
    test "accepts {:ok, float} format and returns {:ok, list_of_tuples}" do
      entities = [1, 2, 3, 4, 5]
      context = %{}

      assert {:ok, results} = SimpleFitness.batch_evaluate(entities, context)
      assert length(results) == length(entities)
      assert results == [{1, 1.0}, {2, 2.0}, {3, 3.0}, {4, 4.0}, {5, 5.0}]
    end

    test "preserves entity order and pairing" do
      entities = [10, 5, 20, 1]
      context = %{}

      assert {:ok, results} = SimpleFitness.batch_evaluate(entities, context)
      assert results == [{10, 10.0}, {5, 5.0}, {20, 20.0}, {1, 1.0}]
    end

    test "handles empty list" do
      assert {:ok, []} = SimpleFitness.batch_evaluate([], %{})
    end

    test "handles single entity" do
      assert {:ok, [{42, 42.0}]} = SimpleFitness.batch_evaluate([42], %{})
    end
  end

  describe "batch_evaluate default implementation with metadata format" do
    test "accepts {:ok, %{score: float}} format and extracts scores" do
      entities = ["hello", "world", "test"]
      context = %{}

      assert {:ok, results} = MetadataFitness.batch_evaluate(entities, context)
      assert length(results) == length(entities)
      assert results == [{"hello", 0.5}, {"world", 0.5}, {"test", 0.4}]
    end

    test "discards metadata and only returns entity-score tuples" do
      entities = ["metadata"]
      context = %{}

      assert {:ok, [{entity, score}]} = MetadataFitness.batch_evaluate(entities, context)
      assert entity == "metadata"
      assert score == 0.8
      assert is_float(score)
    end
  end

  describe "batch_evaluate with mixed formats" do
    test "handles mixed {:ok, float} and {:ok, %{score: float}} in same batch" do
      entities = [5, "hello", 10, "world"]
      context = %{}

      assert {:ok, results} = MixedFitness.batch_evaluate(entities, context)
      assert length(results) == 4
      assert results == [{5, 5.0}, {"hello", 0.5}, {10, 10.0}, {"world", 0.5}]
    end

    test "mixed formats maintain entity-score correspondence" do
      entities = ["a", 1, "abc", 2]
      context = %{}

      assert {:ok, results} = MixedFitness.batch_evaluate(entities, context)

      Enum.each(results, fn {entity, score} ->
        case entity do
          s when is_binary(s) -> assert score == String.length(s) / 10.0
          n when is_number(n) -> assert score == n * 1.0
        end
      end)
    end
  end

  describe "batch_evaluate error handling" do
    test "invalid result (not {:ok, _}) raises with descriptive message" do
      entities = [1]
      context = %{return: :invalid_return}

      assert_raise RuntimeError, ~r/Invalid fitness result: :invalid_return/, fn ->
        InvalidFitness.batch_evaluate(entities, context)
      end
    end

    test "nil result raises with descriptive message" do
      entities = [1]
      context = %{}

      assert_raise RuntimeError, ~r/Invalid fitness result: nil/, fn ->
        InvalidFitness.batch_evaluate(entities, context)
      end
    end

    test "malformed tuple raises with descriptive message" do
      entities = [1]
      context = %{return: {:ok, "not a number"}}

      assert_raise RuntimeError, ~r/Invalid fitness result/, fn ->
        InvalidFitness.batch_evaluate(entities, context)
      end
    end

    test "malformed metadata map raises with descriptive message" do
      entities = [1]
      context = %{return: {:ok, %{not_score: 5.0}}}

      assert_raise RuntimeError, ~r/Invalid fitness result/, fn ->
        InvalidFitness.batch_evaluate(entities, context)
      end
    end

    test "{:error, reason} from evaluate/2 raises" do
      entities = ["valid", :invalid]
      context = %{}

      assert_raise RuntimeError, ~r/Invalid fitness result: {:error, :invalid_entity}/, fn ->
        SimpleFitness.batch_evaluate(entities, context)
      end
    end

    test "raises on first invalid entity in batch" do
      entities = [1, 2, :invalid, 4]
      context = %{}

      assert_raise RuntimeError, fn ->
        SimpleFitness.batch_evaluate(entities, context)
      end
    end
  end

  describe "__using__ macro injection" do
    test "injects batch_evaluate/2 function" do
      assert function_exported?(SimpleFitness, :batch_evaluate, 2)
      assert function_exported?(MetadataFitness, :batch_evaluate, 2)
    end

    test "batch_evaluate is overridable" do
      defmodule CustomBatchFitness do
        use Kaizen.Fitness

        def evaluate(n, _context), do: {:ok, n * 1.0}

        def batch_evaluate(entities, _context) do
          {:ok, Enum.map(entities, fn e -> {e, 100.0} end)}
        end
      end

      assert {:ok, results} = CustomBatchFitness.batch_evaluate([1, 2, 3], %{})
      assert results == [{1, 100.0}, {2, 100.0}, {3, 100.0}]
    end

    test "sets @behaviour Kaizen.Fitness" do
      assert SimpleFitness.__info__(:attributes)[:behaviour] == [Kaizen.Fitness]
    end
  end

  describe "batch_evaluate result format validation" do
    test "returns {:ok, list} tuple" do
      result = SimpleFitness.batch_evaluate([1, 2], %{})
      assert match?({:ok, _list}, result)
    end

    test "list contains {entity, score} tuples" do
      {:ok, results} = SimpleFitness.batch_evaluate([1, 2, 3], %{})

      Enum.each(results, fn result ->
        assert match?({_entity, score} when is_float(score), result)
      end)
    end

    test "result list length matches input list length" do
      entities = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      {:ok, results} = SimpleFitness.batch_evaluate(entities, %{})

      assert length(results) == length(entities)
    end

    test "all scores are floats" do
      {:ok, results} = SimpleFitness.batch_evaluate([1, 2, 3], %{})

      Enum.each(results, fn {_entity, score} ->
        assert is_float(score)
      end)
    end
  end

  describe "edge cases" do
    test "handles negative scores" do
      entities = [-5, -10, -1]
      {:ok, results} = SimpleFitness.batch_evaluate(entities, %{})

      assert results == [{-5, -5.0}, {-10, -10.0}, {-1, -1.0}]
    end

    test "handles zero scores" do
      entities = [0, 0, 0]
      {:ok, results} = SimpleFitness.batch_evaluate(entities, %{})

      assert results == [{0, 0.0}, {0, 0.0}, {0, 0.0}]
    end

    test "handles very large scores" do
      entities = [1_000_000]
      {:ok, results} = SimpleFitness.batch_evaluate(entities, %{})

      assert results == [{1_000_000, 1_000_000.0}]
    end

    test "handles float precision" do
      defmodule PrecisionFitness do
        use Kaizen.Fitness

        def evaluate(n, _context), do: {:ok, n / 3.0}
      end

      entities = [1, 2, 3]
      {:ok, results} = PrecisionFitness.batch_evaluate(entities, %{})

      Enum.each(results, fn {entity, score} ->
        assert_in_delta score, entity / 3.0, 0.0001
      end)
    end
  end
end
