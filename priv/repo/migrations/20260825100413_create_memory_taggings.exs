defmodule Memovee.Repo.Migrations.CreateMemoryTaggings do
  use Ecto.Migration

  def change do
    create table(:memory_taggings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :post_id, references(:memory_posts, on_delete: :delete_all, type: :binary_id),
        null: false

      add :tag_id, references(:memory_tags, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:memory_taggings, [:post_id, :tag_id])
    create index(:memory_taggings, [:tag_id])
  end
end
