defmodule Memovee.Cache do
  @moduledoc "Application-local cache backed by Nebulex."

  use Nebulex.Cache,
    otp_app: :memovee,
    adapter: Nebulex.Adapters.Local
end
