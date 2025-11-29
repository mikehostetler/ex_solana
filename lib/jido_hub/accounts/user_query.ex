defmodule JidoHub.Accounts.UserQuery do
  @moduledoc """
  Query helpers for User resource using Ash Framework patterns.
  """

  import Ash.Query

  alias JidoHub.Accounts.User

  @doc """
  Filters users to only those who are active (not suspended and not deleted).
  """
  def active?(query \\ User) do
    query
    |> filter(is_suspended == false)
    |> filter(is_deleted == false)
  end

  @doc """
  Filters users based on marketing notification subscription status.

  Note: The User schema does not currently have a marketing opt-in field.
  This function is a placeholder that returns all users.
  When a marketing_opt_in or similar field is added, update this function.
  """
  def subscribed_to_marketing_notifications?(query, _status) do
    query
  end

  @doc """
  Orders the query results by the specified field and direction.

  ## Examples

      UserQuery.order_by(query, :inserted_at, :desc)
      UserQuery.order_by(query, :email, :asc)
  """
  def order_by(query, field, direction \\ :asc) do
    sort(query, [{field, direction}])
  end

  @doc """
  Limits the number of results returned.
  """
  def limit(query, count) do
    Ash.Query.limit(query, count)
  end
end
