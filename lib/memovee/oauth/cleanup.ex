defmodule Memovee.OAuth.Cleanup do
  @moduledoc "Bounded periodic cleanup for expired OAuth protocol state."

  use GenServer

  alias Memovee.Accounts.Token.Manager, as: TokenManager
  alias Memovee.OAuth
  alias Memovee.OAuth.Client.Registration.Manager, as: RegistrationManager
  alias Memovee.OAuth.Client.ReplayStore
  alias Memovee.OAuth.Code.Manager, as: CodeManager
  alias Memovee.OAuth.Event
  alias Memovee.OAuth.Grant.Manager, as: GrantManager
  alias Memovee.OAuth.Request.Manager, as: RequestManager
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
      with {:ok, replay_continuation?} <- ReplayStore.cleanup(now, credential_batch_size),
           {:ok, code_continuation?} <- CodeManager.cleanup(now, credential_batch_size),
           {:ok, token_continuation?} <- TokenManager.cleanup_oauth(now, credential_batch_size),
           {:ok, request_continuation?} <- RequestManager.cleanup(now),
           {:ok, grant_continuation?} <-
             GrantManager.cleanup_revoked(now, grant_batch_size) do
        registration_continuation? = RegistrationManager.cleanup_abandoned(now)

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
end
