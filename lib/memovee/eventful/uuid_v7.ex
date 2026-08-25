defmodule Memovee.Eventful.UUIDv7 do
  @moduledoc false

  use Ecto.Type

  @impl Ecto.Type
  def type, do: :uuid

  @impl Ecto.Type
  def cast(value), do: Ecto.UUID.cast(value)

  @impl Ecto.Type
  def dump(value), do: Ecto.UUID.dump(value)

  @impl Ecto.Type
  def load(value), do: Ecto.UUID.load(value)

  @impl Ecto.Type
  def autogenerate do
    Ecto.UUID.generate(version: 7, precision: :monotonic)
  end
end
