defmodule Memovee.OAuth.Access do
  @moduledoc "Associates an Actor token reference with an OAuth grant and rotation family."

  use Memovee.Schema

  alias Memovee.Accounts.Token, as: ActorToken
  alias Memovee.OAuth.Grant

  @primary_key false
  schema "oauth_accesses" do
    belongs_to :actor_token, ActorToken, primary_key: true
    belongs_to :oauth_grant, Grant
    field :family_id, Ecto.UUID
    field :generation, :integer, default: 0
    field :rotated_at, :utc_datetime_usec
  end

  def changeset(%ActorToken{} = actor_token, %Grant{} = grant, attrs \\ %{}) do
    %__MODULE__{}
    |> cast(attrs, [:family_id, :generation, :rotated_at])
    |> put_change(:actor_token_id, actor_token.id)
    |> put_change(:oauth_grant_id, grant.id)
    |> validate_required([:actor_token_id, :oauth_grant_id, :family_id])
    |> validate_number(:generation, greater_than_or_equal_to: 0)
    |> unique_constraint(:actor_token_id, name: :oauth_accesses_pkey)
    |> foreign_key_constraint(:actor_token_id)
    |> foreign_key_constraint(:oauth_grant_id)
  end
end
