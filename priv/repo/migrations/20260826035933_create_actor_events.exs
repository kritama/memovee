defmodule Memovee.Repo.Migrations.CreateActorEvents do
  use Ecto.Migration

  def change do
    alter table(:actors) do
      add :current_state_version, :integer, null: false, default: 0
    end

    create constraint(:actors, :actors_current_state_version_non_negative,
             check: "current_state_version >= 0"
           )

    create index(:actors, [:current_state])

    create table(:transitioning_actor_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :domain, :string, null: false
      add :metadata, :map, null: false, default: %{}

      add :transitioning_actor_id,
          references(:actors, on_delete: :restrict, type: :binary_id),
          null: false

      add :actor_id, references(:actors, on_delete: :restrict, type: :binary_id), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:transitioning_actor_events, [:transitioning_actor_id])
    create index(:transitioning_actor_events, [:actor_id])
    create index(:transitioning_actor_events, [:name, :domain])
  end
end
