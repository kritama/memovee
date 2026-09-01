defmodule Memovee.OAuth.Cleanup do
  @moduledoc "Bounded periodic cleanup for expired OAuth protocol state."

  use GenServer

  alias Memovee.Accounts.Token.Manager, as: TokenManager
  alias Memovee.OAuth
  alias Memovee.OAuth.Access.Manager, as: AccessManager
  alias Memovee.OAuth.Client.Registration.Manager, as: RegistrationManager
  alias Memovee.OAuth.Client.Replay.Manager, as: ReplayManager
  alias Memovee.OAuth.Code.Manager, as: CodeManager
  alias Memovee.OAuth.Event
  alias Memovee.OAuth.Grant.Manager, as: GrantManager
  alias Memovee.OAuth.Request.Manager, as: RequestManager
  alias Memovee.OAuth.Tama.MCP
  alias Memovee.Repo

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
    credential_batch_size = OAuth.config(:credential_cleanup_batch_size)
    grant_batch_size = OAuth.config(:revoked_grant_cleanup_batch_size)

    Repo.transact(fn ->
      with {:ok, replay_continuation?} <- ReplayManager.cleanup(now, credential_batch_size),
           {:ok, grant_continuation?} <-
             GrantManager.cleanup_revoked(now, grant_batch_size),
           {:ok, code_continuation?} <- cleanup_codes(now, credential_batch_size),
           {:ok, token_continuation?} <- cleanup_tokens(now, credential_batch_size),
           {:ok, request_continuation?} <- RequestManager.cleanup(now) do
        registration_continuation? = cleanup_registrations(now)

        {:ok,
         Enum.any?([
           replay_continuation?,
           code_continuation?,
           token_continuation?,
           request_continuation?,
           grant_continuation?,
           registration_continuation?
         ])}
      end
    end)
  rescue
    error ->
      Event.emit(:cleanup_failed, %{reason: :database_error})
      {:error, error}
  end

  defp schedule do
    Process.send_after(self(), :cleanup, OAuth.config(:cleanup_interval_ms, :timer.minutes(15)))
  end

  defp schedule_continuation do
    Process.send_after(self(), :cleanup, :timer.seconds(1))
  end

  defp cleanup_registrations(now) do
    if MCP.configured?(), do: RegistrationManager.cleanup_abandoned(now), else: false
  end

  defp cleanup_codes(now, batch_size) do
    candidates = CodeManager.cleanup_candidates(now, batch_size)

    with :ok <- cleanup_candidates(candidates, &CodeManager.delete_if_expired(&1, now)) do
      {:ok, length(candidates) == batch_size}
    end
  end

  defp cleanup_tokens(now, batch_size) do
    candidates = AccessManager.token_cleanup_candidates(now, batch_size)

    with :ok <- cleanup_candidates(candidates, &TokenManager.delete_oauth_if_expired(&1, now)) do
      {:ok, length(candidates) == batch_size}
    end
  end

  defp cleanup_candidates(candidates, delete_candidate) do
    candidates
    |> Enum.sort_by(fn {id, grant_id} -> {grant_id, id} end)
    |> Enum.reduce_while(:ok, &cleanup_candidate(&1, &2, delete_candidate))
  end

  defp cleanup_candidate({id, grant_id}, :ok, delete_candidate) do
    case GrantManager.lock(grant_id) do
      {:ok, _grant} ->
        :ok = delete_candidate.(id)
        {:cont, :ok}

      {:error, :invalid_grant} ->
        {:cont, :ok}
    end
  end
end
