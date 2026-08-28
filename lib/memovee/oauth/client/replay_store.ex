defmodule Memovee.OAuth.Client.ReplayStore do
  @moduledoc false

  @behaviour TamaOAuth.ReplayStore

  alias Memovee.OAuth.Client.Replay
  alias Memovee.Repo

  @impl true
  def claim(digest, expires_at) when is_binary(digest) do
    case Repo.insert(Replay.changeset(%Replay{}, digest, expires_at)) do
      {:ok, _replay} ->
        :ok

      {:error, changeset} ->
        if replayed?(changeset), do: {:error, :replayed}, else: {:error, :unavailable}
    end
  rescue
    _error -> {:error, :unavailable}
  end

  defp replayed?(changeset) do
    Enum.any?(changeset.errors, fn
      {:digest, {_message, options}} -> options[:constraint] == :unique
      _error -> false
    end)
  end
end
