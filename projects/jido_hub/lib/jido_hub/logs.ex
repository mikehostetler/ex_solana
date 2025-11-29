defmodule JidoHub.Logs do
  use Ash.Domain, otp_app: :jido_hub, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource JidoHub.Logs.Log
  end

  @doc """
  Create a log entry synchronously.

  ## Examples

      JidoHub.Logs.log(%{action: "user.created", user: user})
      JidoHub.Logs.log(%{action: "org.deleted", user_id: user_id, org: org})
  """
  def log(attrs, opts \\ []) do
    attrs
    |> build_attrs()
    |> JidoHub.Logs.Log.create(opts)
  end

  @doc """
  Create a log entry asynchronously.

  ## Examples

      JidoHub.Logs.log_async(%{action: "user.login", user: user})
  """
  def log_async(attrs, opts \\ []) do
    %{attrs: attrs, opts: opts}
    |> JidoHub.Logs.Workers.LogWorker.new()
    |> Oban.insert()
  end

  @doc """
  List logs with optional filters.

  ## Examples

      JidoHub.Logs.list_logs(%{action: "user.login"}, actor: admin_user)
      JidoHub.Logs.list_logs(%{user_id: user_id, org_id: org_id}, actor: admin_user)
  """
  def list_logs(filters \\ %{}, opts \\ []) do
    limit = Keyword.get(opts, :limit)
    actor = Keyword.get(opts, :actor)

    query =
      JidoHub.Logs.Log
      |> Ash.Query.for_read(:by_filters, filters)
      |> then(fn query ->
        if limit, do: Ash.Query.limit(query, limit), else: query
      end)

    Ash.read(query, actor: actor)
  end

  @doc """
  Subscribe to log events via Phoenix PubSub.

  ## Examples

      JidoHub.Logs.subscribe()
  """
  def subscribe do
    Phoenix.PubSub.subscribe(JidoHub.PubSub, "logs")
  end

  @doc """
  Build attributes for log creation, handling user/organization extraction.

  Accepts:
  - `user` or `user_id` - The user performing the action
  - `organization`, `org`, `org_id` - The organization context
  - `target_user` or `target_user_id` - The user being acted upon
  - `action` - The action being logged (required)
  - `metadata` - Additional metadata (optional)

  Determines user_type:
  - "system" if no user provided
  - "admin" if user has :admin role
  - "user" otherwise
  """
  def build_attrs(attrs) when is_map(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    user_id = extract_user_id(attrs)
    org_id = extract_org_id(attrs)
    target_user_id = extract_target_user_id(attrs)
    user_type = determine_user_type(attrs, user_id)

    %{
      action: attrs["action"],
      user_type: user_type,
      metadata: Map.get(attrs, "metadata", %{}),
      user_id: user_id,
      org_id: org_id,
      target_user_id: target_user_id
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp extract_user_id(attrs) do
    cond do
      attrs["user_id"] -> attrs["user_id"]
      attrs["user"] && is_map(attrs["user"]) -> Map.get(attrs["user"], :id)
      true -> nil
    end
  end

  defp extract_org_id(attrs) do
    cond do
      attrs["org_id"] ->
        attrs["org_id"]

      attrs["organization"] && is_map(attrs["organization"]) ->
        Map.get(attrs["organization"], :id)

      attrs["org"] && is_map(attrs["org"]) ->
        Map.get(attrs["org"], :id)

      true ->
        nil
    end
  end

  defp extract_target_user_id(attrs) do
    cond do
      attrs["target_user_id"] -> attrs["target_user_id"]
      attrs["target_user"] && is_map(attrs["target_user"]) -> Map.get(attrs["target_user"], :id)
      true -> nil
    end
  end

  defp determine_user_type(_attrs, nil), do: "system"

  defp determine_user_type(attrs, _user_id) do
    case attrs["user"] do
      %{role: :admin} -> "admin"
      _ -> "user"
    end
  end
end
