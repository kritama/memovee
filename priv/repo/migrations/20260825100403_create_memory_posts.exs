defmodule Memovee.Repo.Migrations.CreateMemoryPosts do
  use Ecto.Migration

  def change do
    create table(:memory_posts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :body, :text, null: false
      add :body_hash, :string, size: 64, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create constraint(:memory_posts, :memory_posts_body_non_blank, check: "btrim(body) <> ''")

    create constraint(:memory_posts, :memory_posts_body_hash_format,
             check: "body_hash ~ '^[0-9a-f]{64}$'"
           )
  end
end
