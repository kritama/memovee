defmodule Memovee.OAuth.Request.ManagerTest do
  use Memovee.DataCase, async: false

  import Memovee.AccountsFixtures
  import Memovee.OAuthFixtures

  alias Memovee.OAuth
  alias Memovee.OAuth.Cleanup
  alias Memovee.OAuth.Request
  alias Memovee.OAuth.Request.Event
  alias Memovee.Repo
  alias TamaOAuth.Crypto

  test "cleanup deletes terminal requests and events only after retention" do
    scope = user_scope_fixture()
    approved = approve_request(scope)
    denied = deny_request(scope)
    recent = deny_request(scope)

    mark_expired_at(approved, DateTime.add(OAuth.now(), -25, :hour))
    mark_expired_at(denied, DateTime.add(OAuth.now(), -25, :hour))
    mark_expired_at(recent, DateTime.add(OAuth.now(), -23, :hour))

    assert Repo.get_by!(Event, oauth_request_id: approved.id)
    assert Repo.get_by!(Event, oauth_request_id: denied.id)
    assert Repo.get_by!(Event, oauth_request_id: recent.id)

    assert {:ok, :ok} = Cleanup.run_once()

    refute Repo.get(Request, approved.id)
    refute Repo.get(Request, denied.id)
    refute Repo.get_by(Event, oauth_request_id: approved.id)
    refute Repo.get_by(Event, oauth_request_id: denied.id)
    assert Repo.get!(Request, recent.id)
    assert Repo.get_by!(Event, oauth_request_id: recent.id)
  end

  test "cleanup expires and reclaims abandoned pending requests" do
    assert {:ok, handle} = OAuth.start_authorization(authorization_params())
    request = request_for_handle(handle)
    mark_expired_at(request, DateTime.add(OAuth.now(), -25, :hour))

    assert {:ok, :ok} = Cleanup.run_once()

    refute Repo.get(Request, request.id)
    refute Repo.get_by(Event, oauth_request_id: request.id)
  end

  test "cleanup processes a configured bounded request batch" do
    original_config = Application.fetch_env!(:memovee, OAuth)

    on_exit(fn -> Application.put_env(:memovee, OAuth, original_config) end)

    Application.put_env(
      :memovee,
      OAuth,
      Keyword.put(original_config, :authorization_request_cleanup_batch_size, 1)
    )

    scope = user_scope_fixture()
    first = deny_request(scope)
    second = deny_request(scope)
    old = DateTime.add(OAuth.now(), -25, :hour)
    mark_expired_at(first, old)
    mark_expired_at(second, old)

    assert {:ok, :ok} = Cleanup.run_once()
    assert Repo.aggregate(Request, :count) == 1

    assert {:ok, :ok} = Cleanup.run_once()
    assert Repo.aggregate(Request, :count) == 0
  end

  defp approve_request(scope) do
    assert {:ok, handle} = OAuth.start_authorization(authorization_params())
    assert {:ok, _redirect_uri} = OAuth.approve(scope, handle)
    request_for_handle(handle)
  end

  defp deny_request(scope) do
    assert {:ok, handle} = OAuth.start_authorization(authorization_params())
    assert {:ok, _redirect_uri} = OAuth.deny(scope, handle)
    request_for_handle(handle)
  end

  defp request_for_handle(handle) do
    Repo.get_by!(Request, handle_digest: Crypto.digest(handle))
  end

  defp mark_expired_at(request, expired_at) do
    Request
    |> where([current], current.id == ^request.id)
    |> Repo.update_all(set: [expires_at: expired_at])
  end
end
