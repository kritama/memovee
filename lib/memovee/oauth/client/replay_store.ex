defmodule Memovee.OAuth.Client.ReplayStore do
  @moduledoc false

  @behaviour TamaOAuth.ReplayStore

  alias Memovee.OAuth.Client.Replay.Manager

  @impl true
  def claim(digest, expires_at) when is_binary(digest) do
    Manager.claim(digest, expires_at)
  rescue
    _error -> {:error, :unavailable}
  end
end
