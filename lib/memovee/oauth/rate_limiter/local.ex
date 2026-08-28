defmodule Memovee.OAuth.RateLimiter.Local do
  @moduledoc false

  use Hammer, backend: :ets
end
