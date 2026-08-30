defmodule Memovee.Repo.Migrations.AddRefreshTokenAllowedToOauthCodes do
  use Ecto.Migration

  def change do
    alter table(:oauth_codes) do
      add :refresh_token_allowed, :boolean, null: false, default: false
    end
  end
end
