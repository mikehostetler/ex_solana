defmodule JidoHub.Accounts do
  use Ash.Domain, otp_app: :jido_hub, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource JidoHub.Accounts.Token
    resource JidoHub.Accounts.User
    resource JidoHub.Accounts.ApiKey
  end
end
