defmodule Memovee.Repo.Migrations.CreateMemoryTags do
  use Ecto.Migration

  def change do
    create table(:memory_tags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :namespace, :string, size: 100, null: false
      add :key, :string, null: false
      add :name, :string, null: false
      add :description, :text
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:memory_tags, [:namespace, :key], name: :memory_tags_namespace_key_index)

    create index(:memory_tags, [:namespace])

    create constraint(:memory_tags, :memory_tags_namespace_format,
             check: "namespace ~ '^[a-z0-9][a-z0-9._-]*$'"
           )

    create constraint(:memory_tags, :memory_tags_key_format,
             check: "key ~ '^[a-z0-9][a-z0-9._-]*$'"
           )

    create constraint(:memory_tags, :memory_tags_name_non_blank, check: "btrim(name) <> ''")
  end
end
