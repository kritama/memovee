defmodule Memovee.Repo.Migrations.CreateActorRelationships do
  use Ecto.Migration

  def change do
    create table(:actor_relationships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false

      add :actor_id, references(:actors, type: :binary_id, on_delete: :restrict), null: false

      add :target_actor_id, references(:actors, type: :binary_id, on_delete: :restrict),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:actor_relationships, :actor_relationships_type_check,
             check: "type = 'owner'"
           )

    create constraint(:actor_relationships, :actor_relationships_distinct_actors_check,
             check: "actor_id <> target_actor_id"
           )

    create index(:actor_relationships, [:actor_id])
    create unique_index(:actor_relationships, [:target_actor_id])
  end
end
