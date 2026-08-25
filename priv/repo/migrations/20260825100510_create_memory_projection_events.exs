defmodule Memovee.Repo.Migrations.CreateMemoryProjectionEvents do
  use Ecto.Migration

  def change do
    create table(:memory_projection_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :domain, :string, null: false
      add :metadata, :map, null: false, default: %{}

      add :projection_id,
          references(:memory_projections, on_delete: :restrict, type: :binary_id),
          null: false

      add :actor_id, references(:actors, on_delete: :restrict, type: :binary_id), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:memory_projection_events, [:projection_id])
    create index(:memory_projection_events, [:actor_id])
    create index(:memory_projection_events, [:name, :domain])
  end
end
