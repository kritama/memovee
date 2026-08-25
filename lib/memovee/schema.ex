defmodule Memovee.Schema do
  @moduledoc """
  Base module for all Ecto schemas in Memovee.

  Standardizes the primary key on time-ordered, strictly monotonic
  UUIDv7 (RFC 9562) and all foreign keys on the `uuid` type, matching
  the `:binary_id` columns created by generated migrations.
  """

  defmacro __using__(_options) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset

      @primary_key {:id, Ecto.UUID, autogenerate: [version: 7, precision: :monotonic]}
      @foreign_key_type Ecto.UUID
    end
  end
end
