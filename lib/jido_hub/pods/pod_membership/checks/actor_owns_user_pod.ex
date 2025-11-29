defmodule JidoHub.Pods.PodMembership.Checks.ActorOwnsUserPod do
  @moduledoc """
  Checks if the actor owns a user-owned pod for PodMembership operations.
  This check works for both creates (using pod_id argument) and updates/destroys (using existing data).
  """

  use Ash.Policy.SimpleCheck

  def describe(_opts), do: "Actor owns the user-owned pod"

  def match?(actor, %{changeset: changeset}, _opts) when not is_nil(actor) do
    pod_id =
      Ash.Changeset.get_argument(changeset, :pod_id) ||
        Ash.Changeset.get_attribute(changeset, :pod_id)

    check_pod_ownership(actor, pod_id)
  end

  def match?(actor, %{query: _query, resource: resource}, _opts) when not is_nil(actor) do
    # For read/update/destroy queries on existing resources
    case resource do
      %{pod_id: pod_id} when not is_nil(pod_id) ->
        check_pod_ownership(actor, pod_id)

      _ ->
        # For bulk queries, we can't check ownership here
        # The filter will be applied by the policy
        false
    end
  end

  def match?(_, _, _), do: false

  defp check_pod_ownership(actor, pod_id) when is_binary(pod_id) do
    case Ash.get(JidoHub.Pods.Pod, pod_id, domain: JidoHub.Pods, authorize?: false) do
      {:ok, pod} ->
        pod.owner_type == :user && pod.owner_id == actor.id

      _ ->
        false
    end
  end

  defp check_pod_ownership(_, _), do: false
end
