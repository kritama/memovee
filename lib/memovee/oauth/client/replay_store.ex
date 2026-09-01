defmodule Memovee.OAuth.Client.ReplayStore do
  @moduledoc false

  @behaviour TamaOAuth.ReplayStore

  alias Memovee.OAuth.Client.Replay.Manager

  @impl true
  def claim(digest, %DateTime{} = expires_at) when is_binary(digest) do
    Manager.claim(digest, normalize_microsecond_precision(expires_at))
  rescue
    _error -> {:error, :unavailable}
  end

  defp normalize_microsecond_precision(%DateTime{microsecond: {value, _precision}} = datetime),
    do: %{datetime | microsecond: {value, 6}}
end
