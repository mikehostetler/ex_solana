defmodule JidoHubWeb.Dashboard.OrgSummary do
  @moduledoc """
  Represents organization summary data for UI display.
  """

  @enforce_keys [:id, :name, :slug]
  defstruct [:id, :name, :slug, :avatar_url]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          slug: String.t(),
          avatar_url: String.t() | nil
        }
end

defmodule JidoHubWeb.Dashboard.Orgs do
  @moduledoc """
  Provides organization data for dashboard UI.
  This contains sample data until real organization integration is implemented.
  """

  alias JidoHubWeb.Dashboard.OrgSummary

  @doc """
  Returns a sample list of organizations for development/demo purposes.
  """
  @spec sample_list() :: [OrgSummary.t()]
  def sample_list do
    [
      %OrgSummary{
        id: "jh",
        name: "JidoHub",
        slug: "jidohub"
      },
      %OrgSummary{
        id: "acme",
        name: "Acme Inc.",
        slug: "acme"
      },
      %OrgSummary{
        id: "orbit",
        name: "Orbit Labs",
        slug: "orbit"
      }
    ]
  end

  @doc """
  Finds an organization by ID from the given list.
  """
  @spec find_by_id([OrgSummary.t()], String.t()) :: OrgSummary.t() | nil
  def find_by_id(orgs, id) do
    Enum.find(orgs, &(&1.id == id))
  end

  @doc """
  Returns the default/first organization from the list.
  """
  @spec default([OrgSummary.t()]) :: OrgSummary.t() | nil
  def default([first | _]), do: first
  def default([]), do: nil
end
