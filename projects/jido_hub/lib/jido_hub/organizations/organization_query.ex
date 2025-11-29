defmodule JidoHub.Organizations.OrganizationQuery do
  @moduledoc """
  Query helpers for Organization resource using Ash Framework patterns.
  """

  import Ash.Query

  alias JidoHub.Organizations.Organization

  @doc """
  Orders the query results by the specified field and direction.

  ## Examples

      OrganizationQuery.order_by(query, :inserted_at, :desc)
      OrganizationQuery.order_by(query, :name, :asc)
  """
  def order_by(query \\ Organization, field, direction \\ :asc) do
    sort(query, [{field, direction}])
  end

  @doc """
  Limits the number of results returned.
  """
  def limit(query, count) do
    Ash.Query.limit(query, count)
  end

  @doc """
  Returns recently created organizations.
  """
  def recent(query \\ Organization, count \\ 10) do
    query
    |> sort(inserted_at: :desc)
    |> Ash.Query.limit(count)
  end
end
