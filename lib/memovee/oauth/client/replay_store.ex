defmodule Memovee.OAuth.Client.ReplayStore do
  @moduledoc false

  @behaviour TamaOAuth.ReplayStore

  import Ecto.Query

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

  def cleanup(now, batch_size) when is_integer(batch_size) and batch_size > 0 do
    ids =
      from(replay in Replay,
        where: replay.expires_at <= ^now,
        order_by: [asc: replay.expires_at, asc: replay.id],
        limit: ^batch_size,
        select: replay.id
      )

    {deleted_count, _replays} =
      Repo.delete_all(from replay in Replay, where: replay.id in subquery(ids))

    {:ok, deleted_count == batch_size}
  end

  defp replayed?(changeset) do
    Enum.any?(changeset.errors, fn
      {:digest, {_message, options}} -> options[:constraint] == :unique
      _error -> false
    end)
  end
end
