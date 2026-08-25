defmodule Memovee.Repo do
  use Ecto.Repo,
    otp_app: :memovee,
    adapter: Ecto.Adapters.Postgres
end
