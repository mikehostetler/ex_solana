defmodule JidoHub.Organizations do
  use Ash.Domain, otp_app: :jido_hub, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource JidoHub.Organizations.Organization
    resource JidoHub.Organizations.Membership
    resource JidoHub.Organizations.Invitation
  end
end
