defmodule JidoHub.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    create index(:pods, [:owner_type, :owner_id])

    create index(:invitations, [:token], where: "accepted_at IS NULL")
  end
end
