defmodule Memovee.Repo.Migrations.CreateActors do
  use Ecto.Migration

  def change do
    create table(:actors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :current_state, :string, null: false, default: "active"

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:actors, :actors_current_state_check,
             check: "current_state IN ('active', 'inactive')"
           )
  end
end
