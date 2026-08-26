defmodule Memovee.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_id, references(:actors, type: :binary_id, on_delete: :restrict), null: false
      add :email, :citext, null: false
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:actor_id])

    create table(:actor_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_id, references(:actors, type: :binary_id, on_delete: :restrict), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :label, :string
      add :authenticated_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:actor_tokens, [:actor_id])
    create index(:actor_tokens, [:actor_id, :context])
    create unique_index(:actor_tokens, [:context, :token])
  end
end
