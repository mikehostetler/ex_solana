defmodule JidoHub.Pods.Pod.Changes.GenerateSlug do
  @moduledoc """
  Generates a unique slug for a pod within the owner's context.
  """

  use Ash.Resource.Change

  require Ash.Query

  def init(opts), do: {:ok, opts}

  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :name) do
      nil ->
        changeset

      name ->
        owner_type = Ash.Changeset.get_attribute(changeset, :owner_type)
        owner_id = Ash.Changeset.get_attribute(changeset, :owner_id)
        current_slug = Ash.Changeset.get_attribute(changeset, :slug)

        base_slug = generate_base_slug(name)

        if current_slug && current_slug == base_slug do
          changeset
        else
          unique_slug =
            ensure_unique_slug(
              changeset.domain,
              base_slug,
              owner_type,
              owner_id,
              changeset.data.id
            )

          Ash.Changeset.change_attribute(changeset, :slug, unique_slug)
        end
    end
  end

  defp generate_base_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s\-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/\-+/, "-")
    |> String.trim("-")
  end

  defp ensure_unique_slug(domain, base_slug, owner_type, owner_id, current_id) do
    ensure_unique_slug(domain, base_slug, owner_type, owner_id, current_id, 0)
  end

  defp ensure_unique_slug(domain, base_slug, owner_type, owner_id, current_id, counter) do
    candidate = if counter == 0, do: base_slug, else: "#{base_slug}-#{counter}"

    query =
      if is_nil(owner_type) or is_nil(owner_id) do
        JidoHub.Pods.Pod
        |> Ash.Query.filter(slug == ^candidate)
      else
        JidoHub.Pods.Pod
        |> Ash.Query.filter(
          owner_type == ^owner_type and
            owner_id == ^owner_id and
            slug == ^candidate
        )
      end

    # Exclude current pod if updating
    query =
      if current_id do
        Ash.Query.filter(query, id != ^current_id)
      else
        query
      end

    case Ash.read(query, domain: domain, authorize?: false) do
      {:ok, []} ->
        candidate

      {:ok, _} ->
        ensure_unique_slug(domain, base_slug, owner_type, owner_id, current_id, counter + 1)

      {:error, _} ->
        candidate
    end
  end
end
