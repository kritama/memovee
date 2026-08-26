defmodule Memovee.Repo.Migrations.CreateActors do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:actors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :identifier, :citext
      add :current_state, :string, null: false, default: "active"

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:actors, :actors_current_state_check,
             check: "current_state IN ('active', 'inactive')"
           )

    create constraint(:actors, :actors_type_check, check: "type IN ('user', 'agent')")

    create constraint(:actors, :actors_identifier_by_type_check,
             check:
               "(type = 'user' AND identifier IS NULL) OR " <>
                 "(type = 'agent' AND NULLIF(BTRIM(identifier::text), '') IS NOT NULL)"
           )

    create unique_index(:actors, [:identifier])
  end
end
