defmodule JidoHub.Pods.Pod.Calculations.Owner do
  @moduledoc """
  Resolves the owner record for a pod.
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
            {:ok, user} -> Map.take(user, [:id, :email, :username])
            {:error, _} -> nil
          end

        :organization ->
          case Ash.get(JidoHub.Organizations.Organization, record.owner_id,
                 domain: JidoHub.Organizations,
                 authorize?: false
               ) do
            {:ok, org} -> Map.take(org, [:id, :name, :slug])
            {:error, _} -> nil
          end
      end
    end)
  end
end
