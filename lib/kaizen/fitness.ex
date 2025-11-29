defmodule Kaizen.Fitness do
  @moduledoc """
  Behaviour for fitness evaluation functions.

  Fitness functions determine how well an entity performs
  against the optimization criteria.
  """

  @type entity :: term()
  @type context :: map()
  @type score :: float()
  @type metadata :: map()
  @type score_map :: %{required(:score) => score(), optional(:metadata) => metadata()}
  @type eval_result :: {:ok, score()} | {:ok, score_map()} | {:error, term()}

  @doc """
  Evaluate a single entity's fitness.

  Returns either a simple score or a score with metadata.
  Higher scores indicate better fitness.

  ## Examples

      def evaluate(text, _context) do
        similarity = String.jaro_distance(text, @target)
        {:ok, similarity}
      end

      def evaluate(text, _context) do
        score = String.jaro_distance(text, @target)
        {:ok, %{score: score, metadata: %{length: String.length(text)}}}
      end
  """
  @callback evaluate(entity(), context()) :: eval_result()

  @doc """
  Batch evaluate multiple entities for efficiency.

  Default implementation calls evaluate/2 for each entity.
  Override for performance when batch evaluation is available.
  """
  @callback batch_evaluate(list(entity()), context()) ::
              {:ok, list({entity(), score()})} | {:error, term()}

  @optional_callbacks [batch_evaluate: 2]

  @doc """
  Compare two entities directly without computing scores.

  This can be more efficient than scoring both entities
  when only relative fitness matters.
  """
  @callback compare(entity(), entity(), context()) ::
              :better | :worse | :equal

  @optional_callbacks [compare: 3]

  @doc """
  Extract score from evaluate/2 result, raising on invalid format.

  Handles both simple scores and score maps with optional metadata.
  """
  @spec score_or_raise!(eval_result()) :: score()
  def score_or_raise!({:ok, score}) when is_number(score), do: score
  def score_or_raise!({:ok, %{score: score}}) when is_number(score), do: score
  def score_or_raise!(other), do: raise("Invalid fitness result: #{inspect(other)}")

  @doc """
  Shared batch evaluation implementation.

  Evaluates multiple entities using the provided module's evaluate/2 callback.
  """
  @spec batch_evaluate(module(), list(entity()), context()) ::
          {:ok, list({entity(), score()})}
  def batch_evaluate(mod, entities, context) do
    results =
      Enum.map(entities, fn entity ->
        {entity, score_or_raise!(mod.evaluate(entity, context))}
      end)

    {:ok, results}
  end

  defmacro __using__(_opts) do
    quote do
      @behaviour Kaizen.Fitness

      @doc """
      Default implementation of batch_evaluate/2 that delegates to shared implementation.

      Raises on invalid fitness results. Override to customize error handling.
      """
      def batch_evaluate(entities, context) do
        Kaizen.Fitness.batch_evaluate(__MODULE__, entities, context)
      end

      defoverridable batch_evaluate: 2
    end
  end
end
