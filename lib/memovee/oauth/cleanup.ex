defmodule Memovee.OAuth.Cleanup do
  @moduledoc "Bounded periodic cleanup for expired OAuth protocol state."

  use GenServer

  import Ecto.Query

  alias Memovee.Accounts.Token
  alias Memovee.OAuth
  alias Memovee.OAuth.{Actor, Client, Code, Event, Grant, Request}
  alias Memovee.OAuth.Client.Registration
  alias Memovee.OAuth.Client.Registration.Event, as: RegistrationEvent
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
      expire_pending_requests(now)
      continuation? = delete_abandoned_client_registrations(now)
      {:ok, continuation?}
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

  defp expire_pending_requests(now) do
    with {:ok, actor} <- Actor.get() do
      Request
      |> where([request], request.current_state == "pending" and request.expires_at <= ^now)
      |> order_by([request], asc: request.expires_at)
      |> limit(@batch_size)
      |> Repo.all()
      |> Enum.each(&Eventful.Transit.perform(&1, actor, "expire"))
    end
  end

  defp delete_abandoned_client_registrations(now) do
    cutoff = DateTime.add(now, -OAuth.config(:registration_abandonment_seconds), :second)
    batch_size = OAuth.config(:registration_cleanup_batch_size)

    registration_ids = registration_cleanup_candidates(cutoff, now, batch_size)

    Enum.each(
      registration_ids,
      &delete_abandoned_client_registration(&1, cutoff, now)
    )

    length(registration_ids) == batch_size
  end

  defp registration_cleanup_candidates(cutoff, now, batch_size) do
    client_id_prefix = OAuth.endpoint("/auth/registrations/")

    from(registration in Registration,
      left_join: request in Request,
      on:
        request.client_id == fragment("? || ?::text", ^client_id_prefix, registration.id) and
          request.current_state == "pending" and request.expires_at > ^now,
      left_join: grant in Grant,
      on:
        grant.oauth_client_id == fragment("? || ?::text", ^client_id_prefix, registration.id) and
          grant.current_state == "active",
      where:
        fragment(
          "COALESCE(?, ?) <= ?",
          registration.last_used_at,
          registration.inserted_at,
          ^cutoff
        ) and is_nil(request.id) and is_nil(grant.id),
      order_by: [
        asc: registration.last_used_at,
        asc: registration.inserted_at,
        asc: registration.id
      ],
      limit: ^batch_size,
      select: registration.id
    )
    |> Repo.all()
  end

  defp delete_abandoned_client_registration(registration_id, cutoff, now) do
    registration =
      Registration
      |> where([registration], registration.id == ^registration_id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    if abandoned_registration?(registration, cutoff) and
         not registration_in_use?(registration, now) do
      Repo.delete_all(
        from(event in RegistrationEvent,
          where: event.oauth_client_registration_id == ^registration.id
        )
      )

      Repo.delete!(registration)
    end
  end

  defp abandoned_registration?(nil, _cutoff), do: false

  defp abandoned_registration?(registration, cutoff) do
    last_used_at = registration.last_used_at || registration.inserted_at
    DateTime.compare(last_used_at, cutoff) in [:lt, :eq]
  end

  defp registration_in_use?(registration, now) do
    client_id = OAuth.endpoint("/auth/registrations/#{registration.id}")

    Repo.exists?(
      from(request in Request,
        where:
          request.client_id == ^client_id and request.current_state == "pending" and
            request.expires_at > ^now
      )
    ) or
      Repo.exists?(
        from(grant in Grant,
          where: grant.oauth_client_id == ^client_id and grant.current_state == "active"
        )
      )
  end

  defp schedule do
    Process.send_after(self(), :cleanup, OAuth.config(:cleanup_interval_ms, :timer.minutes(15)))
  end

  defp schedule_continuation do
    Process.send_after(self(), :cleanup, :timer.seconds(1))
  end
end
