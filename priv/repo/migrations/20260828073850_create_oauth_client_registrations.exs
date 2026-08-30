defmodule Memovee.Repo.Migrations.CreateOauthClientRegistrations do
  use Ecto.Migration

  def change do
    create table(:oauth_client_registrations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :application_type, :string, null: false
      add :client_name, :text, null: false
      add :client_uri, :text
      add :redirect_uris, {:array, :text}, null: false
      add :grant_types, {:array, :text}, null: false
      add :response_types, {:array, :text}, null: false
      add :token_endpoint_auth_method, :string, null: false
      add :scope, :text
      add :metadata_digest, :binary, null: false
      add :current_state, :string, null: false, default: "pending"
      add :current_state_version, :integer, null: false, default: 0
      add :last_used_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:oauth_client_registrations, [:current_state])
    create index(:oauth_client_registrations, [:last_used_at])

    create constraint(:oauth_client_registrations, :oauth_client_registrations_state,
             check: "current_state IN ('pending', 'active', 'inactive')"
           )

    create constraint(:oauth_client_registrations, :oauth_client_registrations_state_version,
             check: "current_state_version >= 0"
           )

    create table(:oauth_client_registration_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :domain, :string, null: false
      add :metadata, :map, null: false, default: %{}

      add :oauth_client_registration_id,
          references(:oauth_client_registrations, type: :binary_id, on_delete: :restrict),
          null: false

      add :actor_id, references(:actors, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:oauth_client_registration_events, [:oauth_client_registration_id])
    create index(:oauth_client_registration_events, [:actor_id])
    create index(:oauth_client_registration_events, [:name, :domain])
  end
end
