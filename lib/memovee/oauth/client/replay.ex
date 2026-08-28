defmodule Memovee.OAuth.Client.Replay do
  @moduledoc "Digest-only replay claim for private-key JWT assertions."

  use Memovee.Schema

  schema "oauth_client_replays" do
    field :digest, :binary, redact: true
    field :expires_at, :utc_datetime_usec
  end

  def changeset(replay, digest, expires_at) do
    replay
    |> change(digest: digest, expires_at: expires_at)
    |> validate_required([:digest, :expires_at])
    |> unique_constraint(:digest)
  end
end
