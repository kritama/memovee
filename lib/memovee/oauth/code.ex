defmodule Memovee.OAuth.Code do
  @moduledoc "A one-time, digest-only OAuth authorization code."

  use Memovee.Schema

  alias Memovee.OAuth.Grant

  schema "oauth_codes" do
    field :code_digest, :binary, redact: true
    field :redirect_uri, :string
    field :resource, :string
    field :scope, :string
    field :code_challenge, :string, redact: true
    field :expires_at, :utc_datetime_usec
    field :consumed_at, :utc_datetime_usec

    belongs_to :oauth_grant, Grant

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(code, attrs) do
    code
    |> cast(attrs, [
      :code_digest,
      :redirect_uri,
      :resource,
      :scope,
      :code_challenge,
      :expires_at,
      :consumed_at
    ])
    |> validate_required([
      :code_digest,
      :oauth_grant_id,
      :redirect_uri,
      :resource,
      :scope,
      :code_challenge,
      :expires_at
    ])
    |> unique_constraint(:code_digest)
    |> foreign_key_constraint(:oauth_grant_id)
  end
end
