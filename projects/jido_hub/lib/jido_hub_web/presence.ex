defmodule JidoHubWeb.Presence do
  @moduledoc false
  use Phoenix.Presence, otp_app: :jido_hub, pubsub_server: JidoHub.PubSub

  alias JidoHub.Accounts.User

  def online_user?(%User{} = user) do
    online = not ("users" |> get_by_key(user.id) |> Enum.empty?())
    {user, online}
  end

  def online_users(users) when is_list(users) do
    Enum.map(users, fn user ->
      {user, online?} = online_user?(user)
      Map.put(user, :is_online, online?)
    end)
  end
end
