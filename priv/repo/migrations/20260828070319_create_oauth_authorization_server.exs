defmodule Memovee.Repo.Migrations.CreateOauthAuthorizationServer do
  use Ecto.Migration

  def change do
    create table(:oauth_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :handle_digest, :binary, null: false
      add :client_id, :text, null: false
      add :client_metadata_digest, :binary, null: false
      add :redirect_uri, :text, null: false
      add :resource, :text, null: false
      add :scope, :string, null: false
      add :state, :text, null: false
      add :code_challenge, :string, null: false
      add :current_state, :string, null: false, default: "pending"
      add :current_state_version, :integer, null: false, default: 0
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:oauth_requests, [:handle_digest])
    create index(:oauth_requests, [:client_id])
    create index(:oauth_requests, [:expires_at])

    create constraint(:oauth_requests, :oauth_requests_state,
             check: "current_state IN ('pending', 'approved', 'denied', 'expired')"
           )

    create constraint(:oauth_requests, :oauth_requests_state_version_non_negative,
             check: "current_state_version >= 0"
           )

    create table(:oauth_grants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_id, references(:actors, type: :binary_id, on_delete: :restrict), null: false
      add :oauth_client_id, :text, null: false
      add :resource, :text, null: false
      add :scope, :string, null: false
      add :current_state, :string, null: false, default: "pending"
      add :current_state_version, :integer, null: false, default: 0
      add :last_used_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:oauth_grants, [:actor_id])
    create index(:oauth_grants, [:oauth_client_id])
    create index(:oauth_grants, [:current_state])

    create unique_index(:oauth_grants, [:actor_id, :oauth_client_id, :resource],
             where: "current_state = 'active'",
             name: :oauth_grants_active_identity_index
           )

    create constraint(:oauth_grants, :oauth_grants_state,
             check: "current_state IN ('pending', 'active', 'revoked')"
           )

    create constraint(:oauth_grants, :oauth_grants_state_version_non_negative,
             check: "current_state_version >= 0"
           )

    create table(:oauth_request_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :domain, :string, null: false
      add :metadata, :map, null: false, default: %{}

      add :oauth_request_id,
          references(:oauth_requests, type: :binary_id, on_delete: :restrict),
          null: false

      add :actor_id, references(:actors, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:oauth_request_events, [:oauth_request_id])
    create index(:oauth_request_events, [:actor_id])
    create index(:oauth_request_events, [:name, :domain])

    create table(:oauth_grant_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :domain, :string, null: false
      add :metadata, :map, null: false, default: %{}

      add :oauth_grant_id,
          references(:oauth_grants, type: :binary_id, on_delete: :restrict),
          null: false

      add :actor_id, references(:actors, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:oauth_grant_events, [:oauth_grant_id])
    create index(:oauth_grant_events, [:actor_id])
    create index(:oauth_grant_events, [:name, :domain])

    create table(:oauth_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code_digest, :binary, null: false

      add :oauth_grant_id,
          references(:oauth_grants, type: :binary_id, on_delete: :restrict),
          null: false

      add :redirect_uri, :text, null: false
      add :resource, :text, null: false
      add :scope, :string, null: false
      add :code_challenge, :string, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :consumed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:oauth_codes, [:code_digest])
    create index(:oauth_codes, [:oauth_grant_id])
    create index(:oauth_codes, [:expires_at])

    create table(:oauth_accesses, primary_key: false) do
      add :actor_token_id,
          references(:actor_tokens, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :oauth_grant_id,
          references(:oauth_grants, type: :binary_id, on_delete: :delete_all),
          null: false

      add :family_id, :binary_id, null: false
      add :generation, :integer, null: false, default: 0
      add :rotated_at, :utc_datetime_usec
    end

    create index(:oauth_accesses, [:oauth_grant_id])
    create index(:oauth_accesses, [:family_id])

    create constraint(:oauth_accesses, :oauth_accesses_generation_non_negative,
             check: "generation >= 0"
           )

    create table(:oauth_client_replays, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :digest, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
    end

    create unique_index(:oauth_client_replays, [:digest])
    create index(:oauth_client_replays, [:expires_at])
  end
end
