defmodule Memovee.OAuth.Client.Registration do
  @moduledoc "Persisted public-client Dynamic Client Registration metadata."

  use Memovee.Schema
  use Eventful.Transitable

  alias __MODULE__.{Event, Transitions}

  Transitions
  |> governs(:current_state, on: Event, lock: :current_state_version)

  schema "oauth_client_registrations" do
    field :application_type, :string
    field :client_name, :string
    field :client_uri, :string
    field :redirect_uris, {:array, :string}
    field :grant_types, {:array, :string}
    field :response_types, {:array, :string}
    field :token_endpoint_auth_method, :string
    field :scope, :string
    field :metadata_digest, :binary
    field :current_state, :string, default: "pending"
    field :current_state_version, :integer, default: 0
    field :last_used_at, :utc_datetime_usec

    has_many :events, Event, foreign_key: :oauth_client_registration_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(registration, attrs) do
    registration
    |> cast(attrs, [
      :application_type,
      :client_name,
      :client_uri,
      :redirect_uris,
      :grant_types,
      :response_types,
      :token_endpoint_auth_method,
      :scope,
      :metadata_digest,
      :last_used_at
    ])
    |> validate_required([
      :application_type,
      :client_name,
      :redirect_uris,
      :grant_types,
      :response_types,
      :token_endpoint_auth_method,
      :metadata_digest
    ])
  end
end
