defmodule Memovee.Repo.Migrations.AddMemoryOwnershipAndIngestions do
  use Ecto.Migration

  def change do
    alter table(:memory_posts) do
      add :owner_actor_id, references(:actors, type: :binary_id, on_delete: :restrict),
        null: false

      add :created_by_actor_id, references(:actors, type: :binary_id, on_delete: :restrict),
        null: false

      add :memory_revision, :integer, null: false, default: 1
    end

    alter table(:memory_tags) do
      add :owner_actor_id, references(:actors, type: :binary_id, on_delete: :restrict),
        null: false
    end

    drop unique_index(:memory_tags, [:namespace, :key])
    create unique_index(:memory_tags, [:owner_actor_id, :namespace, :key])
    create index(:memory_posts, [:owner_actor_id])
    create constraint(:memory_posts, :memory_revision_positive, check: "memory_revision >= 1")

    create table(:memory_ingestions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :owner_actor_id, references(:actors, type: :binary_id, on_delete: :restrict),
        null: false

      add :created_by_actor_id, references(:actors, type: :binary_id, on_delete: :restrict),
        null: false

      add :origin_identifier, :text, null: false
      add :original_content, :text, null: false
      add :source_hash, :string, null: false
      add :saved_receipt, :map
      add :post_id, references(:memory_posts, type: :binary_id, on_delete: :restrict)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:memory_ingestions, [:owner_actor_id, :origin_identifier])
    create unique_index(:memory_ingestions, [:post_id])

    create table(:projections_searches, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :owner_actor_id, references(:actors, type: :binary_id, on_delete: :restrict),
        null: false

      add :post_id, references(:memory_posts, type: :binary_id, on_delete: :restrict), null: false
      add :revision, :integer, null: false
      add :fingerprint, :string, null: false
      add :profile, :string, null: false, default: "memory-v1"
      add :current_state, :string, null: false, default: "pending"
      add :current_state_version, :integer, null: false, default: 0
      add :lease_token, :uuid
      add :description, :text
      add :chunks, {:array, :map}
      add :last_error, :map
      add :indexed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime)
    end

    create unique_index(:projections_searches, [:post_id, :revision, :profile])

    create constraint(:projections_searches, :projection_revision_positive,
             check: "revision >= 1"
           )

    create table(:projections_search_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :domain, :string, null: false
      add :metadata, :map, null: false, default: %{}

      add :search_id,
          references(:projections_searches, type: :binary_id, on_delete: :restrict), null: false

      add :actor_id, references(:actors, type: :binary_id, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:projections_search_events, [:search_id])
    create index(:projections_search_events, [:actor_id])
  end
end
