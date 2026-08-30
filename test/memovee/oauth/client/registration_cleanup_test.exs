defmodule Memovee.OAuth.Client.RegistrationCleanupTest do
  use Memovee.DataCase, async: false

  import Memovee.AccountsFixtures
  import Memovee.OAuthFixtures

  alias Memovee.OAuth
  alias Memovee.OAuth.Cleanup
  alias Memovee.OAuth.Client.Registration
  alias Memovee.OAuth.Client.Registration.Event
  alias Memovee.OAuth.Client.Registration.Manager
  alias Memovee.Repo

  test "fetch records registration usage without writing more than once per touch interval" do
    {registration, client_id} = registration_fixture()
    assert is_nil(registration.last_used_at)

    assert {:ok, _metadata} = Manager.fetch(client_id)
    first_touch = Repo.get!(Registration, registration.id).last_used_at
    assert %DateTime{} = first_touch

    assert {:ok, _metadata} = Manager.fetch(client_id)
    assert Repo.get!(Registration, registration.id).last_used_at == first_touch
  end

  test "cleanup deletes only stale unreferenced registrations and their events" do
    {stale, _stale_client_id} = registration_fixture()
    {recent, _recent_client_id} = registration_fixture()
    {referenced, referenced_client_id} = registration_fixture()
    {pending, pending_client_id} = registration_fixture()
    scope = user_scope_fixture()

    assert {:ok, handle} =
             OAuth.start_authorization(
               authorization_params(%{
                 "client_id" => referenced_client_id,
                 "redirect_uri" => registration_redirect_uri()
               })
             )

    assert {:ok, _redirect_uri} = OAuth.approve(scope, handle)

    assert {:ok, _pending_handle} =
             OAuth.start_authorization(
               authorization_params(%{
                 "client_id" => pending_client_id,
                 "redirect_uri" => registration_redirect_uri()
               })
             )

    mark_stale(stale)
    mark_stale(referenced)
    mark_stale(pending)

    assert Repo.get_by!(Event, oauth_client_registration_id: stale.id)
    assert {:ok, :ok} = Cleanup.run_once()

    refute Repo.get(Registration, stale.id)
    refute Repo.get_by(Event, oauth_client_registration_id: stale.id)
    assert Repo.get!(Registration, recent.id)
    assert Repo.get!(Registration, referenced.id)
    assert Repo.get!(Registration, pending.id)
  end

  test "cleanup processes a configured bounded registration batch" do
    original_config = Application.fetch_env!(:memovee, OAuth)

    on_exit(fn -> Application.put_env(:memovee, OAuth, original_config) end)

    Application.put_env(
      :memovee,
      OAuth,
      Keyword.put(original_config, :registration_cleanup_batch_size, 1)
    )

    {first, _client_id} = registration_fixture()
    {second, _client_id} = registration_fixture()
    mark_stale(first)
    mark_stale(second)

    assert {:ok, :ok} = Cleanup.run_once()
    assert Repo.aggregate(Registration, :count) == 1

    assert {:ok, :ok} = Cleanup.run_once()
    assert Repo.aggregate(Registration, :count) == 0
  end

  defp registration_fixture do
    assert {:ok, response} = Manager.create(registration_params())
    client_id = response["client_id"]
    id = client_id |> URI.parse() |> Map.fetch!(:path) |> Path.basename()
    {Repo.get!(Registration, id), client_id}
  end

  defp registration_params do
    %{
      "application_type" => "native",
      "client_name" => "Cleanup Test Client",
      "redirect_uris" => [registration_redirect_uri()],
      "grant_types" => ["authorization_code", "refresh_token"],
      "response_types" => ["code"],
      "token_endpoint_auth_method" => "none",
      "scope" => "mcp.message"
    }
  end

  defp registration_redirect_uri, do: "http://127.0.0.1:49321/callback"

  defp mark_stale(registration) do
    stale_at = DateTime.add(OAuth.now(), -31, :day)

    Registration
    |> where([current], current.id == ^registration.id)
    |> Repo.update_all(set: [inserted_at: stale_at, last_used_at: stale_at])
  end
end
