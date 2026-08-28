defmodule Memovee.OAuth.Cleanup do
  @moduledoc "Bounded periodic cleanup for expired OAuth protocol state."

  use GenServer

  import Ecto.Query

  alias Memovee.Accounts.Token
  alias Memovee.OAuth
  alias Memovee.OAuth.{Client, Code, Event}
  alias Memovee.OAuth.Client.Registration.Manager, as: RegistrationManager
  alias Memovee.OAuth.Request.Manager, as: RequestManager
  alias Memovee.Repo

  @batch_size 250

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def run_once, do: GenServer.call(__MODULE__, :run_once, 30_000)

  @impl true
  def init(:ok) do
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:run_once, _from, state) do
    result =
      case cleanup() do
        {:ok, _continuation?} -> {:ok, :ok}
        error -> error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    case cleanup() do
      {:ok, true} -> schedule_continuation()
      _result -> schedule()
    end

    {:noreply, state}
  end

  defp cleanup do
    now = OAuth.now()

    Repo.transact(fn ->
      delete_expired_replays(now)
      delete_expired_codes(now)
      delete_expired_tokens(now)

      with {:ok, request_continuation?} <- RequestManager.cleanup(now) do
        registration_continuation? = RegistrationManager.cleanup_abandoned(now)
        {:ok, request_continuation? or registration_continuation?}
      end
    end)
  rescue
    error ->
      Event.emit(:cleanup_failed, %{reason: :database_error})
      {:error, error}
  end

  defp delete_expired_replays(now) do
    ids =
      from(replay in Client.Replay,
        where: replay.expires_at <= ^now,
        order_by: [asc: replay.expires_at],
        limit: @batch_size,
        select: replay.id
      )

    Repo.delete_all(from replay in Client.Replay, where: replay.id in subquery(ids))
  end

  defp delete_expired_codes(now) do
    ids =
      from(code in Code,
        where: code.expires_at <= ^now or not is_nil(code.consumed_at),
        order_by: [asc: code.expires_at],
        limit: @batch_size,
        select: code.id
      )

    Repo.delete_all(from code in Code, where: code.id in subquery(ids))
  end

  defp delete_expired_tokens(now) do
    ids =
      from(token in Token,
        where:
          token.context in ["oauth_access", "oauth_refresh"] and
            (token.expires_at <= ^now or
               (token.context == "oauth_access" and not is_nil(token.revoked_at))),
        order_by: [asc: token.expires_at],
        limit: @batch_size,
        select: token.id
      )

    Repo.delete_all(from token in Token, where: token.id in subquery(ids))
  end

  defp schedule do
    Process.send_after(self(), :cleanup, OAuth.config(:cleanup_interval_ms, :timer.minutes(15)))
  end

  defp schedule_continuation do
    Process.send_after(self(), :cleanup, :timer.seconds(1))
  end
end
