defmodule Memovee.OAuth.Request do
  @moduledoc "Persisted, short-lived OAuth authorization request."

  use Memovee.Schema
  use Eventful.Transitable

  alias __MODULE__.{Event, Transitions}

  Transitions
  |> governs(:current_state, on: Event, lock: :current_state_version)

  schema "oauth_requests" do
    field :handle_digest, :binary, redact: true
    field :client_id, :string
    field :client_metadata_digest, :binary
    field :redirect_uri, :string
    field :resource, :string
    field :scope, :string
    field :state, :string, redact: true
    field :code_challenge, :string, redact: true
    field :current_state, :string, default: "pending"
    field :current_state_version, :integer, default: 0
    field :expires_at, :utc_datetime_usec

    has_many :events, Event, foreign_key: :oauth_request_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :handle_digest,
      :client_id,
      :client_metadata_digest,
      :redirect_uri,
      :resource,
      :scope,
      :state,
      :code_challenge,
      :expires_at
    ])
    |> validate_required([
      :handle_digest,
      :client_id,
      :client_metadata_digest,
      :redirect_uri,
      :resource,
      :scope,
      :state,
      :code_challenge,
      :expires_at
    ])
    |> unique_constraint(:handle_digest)
  end
end
