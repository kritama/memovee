defmodule Memovee.Repo.Migrations.AddMemoryOwnershipAndProjections do
  use Ecto.Migration

  def change do
    alter table(:memory_posts) do
      add :owner_actor_id, references(:actors, type: :binary_id, on_delete: :restrict),
        null: false

      add :created_by_actor_id, references(:actors, type: :binary_id, on_delete: :restrict),
        null: false

      add :origin_identifier, :text
      add :memory_revision, :integer, null: false, default: 1
    end

    alter table(:memory_tags) do
      add :owner_actor_id, references(:actors, type: :binary_id, on_delete: :restrict),
        null: false
    end

    drop unique_index(:memory_tags, [:namespace, :key])
    create unique_index(:memory_tags, [:owner_actor_id, :namespace, :key])
    create index(:memory_posts, [:owner_actor_id])
    create unique_index(:memory_posts, [:owner_actor_id, :origin_identifier])
    create constraint(:memory_posts, :memory_revision_positive, check: "memory_revision >= 1")

    create table(:projections_indexings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :owner_actor_id, references(:actors, type: :binary_id, on_delete: :restrict),
        null: false

      add :post_id, references(:memory_posts, type: :binary_id, on_delete: :restrict), null: false
      add :revision, :integer, null: false
      add :fingerprint, :string, null: false
      add :indexing_version, :integer, null: false, default: 1
      add :current_state, :string, null: false, default: "pending"
      add :current_state_version, :integer, null: false, default: 0
      add :lease_token, :uuid
      add :description, :text
      add :chunks, {:array, :map}
      add :last_error, :map
      add :indexed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime)
    end

    create unique_index(:projections_indexings, [:post_id, :revision, :indexing_version])

    create constraint(:projections_indexings, :indexing_version_positive,
             check: "indexing_version >= 1"
           )

    create constraint(:projections_indexings, :projection_revision_positive,
             check: "revision >= 1"
           )

    create table(:projections_indexing_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :domain, :string, null: false
      add :metadata, :map, null: false, default: %{}

      add :indexing_id,
          references(:projections_indexings, type: :binary_id, on_delete: :restrict), null: false

      add :actor_id, references(:actors, type: :binary_id, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:projections_indexing_events, [:indexing_id])
    create index(:projections_indexing_events, [:actor_id])
  end
end
