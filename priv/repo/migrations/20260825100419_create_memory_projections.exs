defmodule Memovee.Repo.Migrations.CreateMemoryProjections do
  use Ecto.Migration

  def change do
    create table(:memory_projections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :identifier, :string, null: false
      add :tama_space_id, :uuid, null: false
      add :tama_class_id, :uuid, null: false
      add :tama_entity_id, :uuid
      add :synced_body_hash, :string, size: 64
      add :current_state, :string, null: false, default: "pending"
      add :current_state_version, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      add :post_id, references(:memory_posts, on_delete: :restrict, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create constraint(:memory_projections, :memory_projections_state_allowed,
             check: "current_state IN ('pending', 'syncing', 'synced', 'failed')"
           )

    create constraint(:memory_projections, :memory_projections_state_version_non_negative,
             check: "current_state_version >= 0"
           )

    create constraint(:memory_projections, :memory_projections_synced_body_hash_format,
             check: "synced_body_hash IS NULL OR synced_body_hash ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:memory_projections, :memory_projections_identifier_non_blank,
             check: "btrim(identifier) <> ''"
           )

    create unique_index(:memory_projections, [:post_id, :tama_space_id, :tama_class_id],
             name: :memory_projections_post_target_index
           )

    create unique_index(:memory_projections, [:tama_space_id, :tama_class_id, :identifier],
             name: :memory_projections_target_identifier_index
           )

    create unique_index(:memory_projections, [:tama_entity_id],
             where: "tama_entity_id IS NOT NULL",
             name: :memory_projections_tama_entity_id_index
           )

    create index(:memory_projections, [:current_state])
    create index(:memory_projections, [:tama_space_id, :tama_class_id])
  end
end
