defmodule JidoHub.Organizations.Organization.Changes.GenerateSlug do
  @moduledoc """
  Generates a unique URL-safe slug from the organization name.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :name) do
      nil ->
        changeset

      name when is_binary(name) ->
        slug = generate_slug(name)
        unique_slug = ensure_unique_slug(changeset, slug)
        Ash.Changeset.change_attribute(changeset, :slug, unique_slug)

      _ ->
        changeset
    end
  end

  defp generate_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s\-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  defp ensure_unique_slug(changeset, base_slug) do
    domain = changeset.domain

    case check_slug_exists(domain, base_slug, changeset) do
      false -> base_slug
      true -> find_unique_slug(domain, base_slug, changeset, 1)
    end
  end

  defp find_unique_slug(domain, base_slug, changeset, counter) do
    candidate = "#{base_slug}-#{counter}"

    case check_slug_exists(domain, candidate, changeset) do
      false -> candidate
      true -> find_unique_slug(domain, base_slug, changeset, counter + 1)
    end
  end

  defp check_slug_exists(domain, slug, changeset) do
    query = JidoHub.Organizations.Organization

    # Exclude current record if this is an update
    query =
      case Ash.Changeset.get_attribute(changeset, :id) do
        nil -> query
        id -> Ash.Query.filter(query, id != ^id)
      end

    query
    |> Ash.Query.filter(slug == ^slug)
    |> Ash.Query.limit(1)
    |> Ash.read!(domain: domain, authorize?: false)
    |> case do
      [] -> false
      _ -> true
    end
  end
end
