defmodule JidoHub.Pods do
  @moduledoc """
  The Pods domain for managing workspaces that can be owned by users or organizations.
  """

  use Ash.Domain,
    otp_app: :jido_hub,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource JidoHub.Pods.Pod
    resource JidoHub.Pods.PodMembership
  end
end
