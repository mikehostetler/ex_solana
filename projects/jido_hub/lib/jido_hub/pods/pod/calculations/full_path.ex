defmodule JidoHub.Pods.Pod.Calculations.FullPath do
  @moduledoc """
  Calculates the full path for a pod based on owner type.
  """

  use Ash.Resource.Calculation

  require Ash.Query

  def init(opts), do: {:ok, opts}

  def calculate(records, _opts, %{domain: _domain}) do
    Enum.map(records, fn record ->
      case record.owner_type do
        :user ->
          case Ash.get(JidoHub.Accounts.User, record.owner_id,
                 domain: JidoHub.Accounts,
                 authorize?: false
               ) do
            {:ok, user} ->
              "@#{user.username}/#{record.slug}"

            {:error, _} ->
              "unknown/#{record.slug}"
          end

        :organization ->
          case Ash.get(JidoHub.Organizations.Organization, record.owner_id,
                 domain: JidoHub.Organizations,
                 authorize?: false
               ) do
            {:ok, org} ->
              "@#{org.slug}/#{record.slug}"

            {:error, _} ->
              "unknown/#{record.slug}"
          end
      end
    end)
  end
end
