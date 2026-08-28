defmodule Memovee.OAuth.AuthorizationTest do
  use Memovee.DataCase, async: false

  import Memovee.AccountsFixtures
  import Memovee.OAuthFixtures

  alias Memovee.Accounts.Token
  alias Memovee.OAuth
  alias Memovee.OAuth.{Code, Grant, KeyProvider, Request}
  alias Memovee.Repo

  test "persists only request and code digests through approval" do
    scope = user_scope_fixture()

    assert {:ok, handle} = OAuth.start_authorization(authorization_params())
    assert %Request{} = request = Repo.one!(Request)
    refute request.handle_digest == handle
    assert request.current_state == "pending"

    assert {:ok, consent} = OAuth.consent(scope, handle)
    assert consent.client_name == "Test MCP Client"
    assert consent.request.scope == "mcp.message"

    assert {:ok, redirect_uri} = OAuth.approve(scope, handle)
    query = redirect_uri |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    code = Map.fetch!(query, "code")

    assert query["state"] == "opaque-client-state"
    assert query["iss"] == OAuth.issuer()
    assert Repo.one!(Request).current_state == "approved"
    assert Repo.one!(Grant).current_state == "active"
    refute Repo.one!(Code).code_digest == code
  end

  test "denial preserves state and issuer without creating a grant" do
    scope = user_scope_fixture()
    assert {:ok, handle} = OAuth.start_authorization(authorization_params())
    assert {:ok, redirect_uri} = OAuth.deny(scope, handle)

    query = redirect_uri |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["error"] == "access_denied"
    assert query["state"] == "opaque-client-state"
    assert query["iss"] == OAuth.issuer()
    assert Repo.one!(Request).current_state == "denied"
    refute Repo.exists?(Grant)
  end

  test "an authorization code is consumed exactly once" do
    scope = user_scope_fixture()
    %{code: code} = authorize(scope)

    assert {:ok, _tokens} = exchange_code(code)
    assert {:error, %TamaOAuth.Error{code: :invalid_grant}} = exchange_code(code)
  end

  test "concurrent approval creates only one grant and one code" do
    scope = user_scope_fixture()
    assert {:ok, handle} = OAuth.start_authorization(authorization_params())

    results =
      [scope, scope]
      |> Task.async_stream(&OAuth.approve(&1, handle), timeout: :infinity)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _redirect}, &1)) == 1
    assert Repo.aggregate(Grant, :count) == 1
    assert Repo.aggregate(Code, :count) == 1
  end

  test "authorization code exchange issues a JWT and digest-only rotating refresh token" do
    scope = user_scope_fixture()
    %{code: code} = authorize(scope)

    assert {:ok, first} = exchange_code(code)
    assert first["token_type"] == "Bearer"
    assert first["scope"] == "mcp.message"
    assert first["expires_in"] == 600

    raw_refresh_token = first["refresh_token"]
    refute Repo.exists?(from token in Token, where: token.token == ^raw_refresh_token)

    assert {:ok, jwks} = KeyProvider.public_jwks()

    assert {:ok, claims} =
             TamaOAuth.JWT.verify_access_token(first["access_token"], jwks,
               issuer: OAuth.issuer(),
               audience: OAuth.resource(),
               scopes: ["mcp.message"]
             )

    assert claims["sub"] == scope.actor.id
    assert claims["client_id"] == client_id()

    assert {:ok, second} =
             OAuth.exchange(%{
               "grant_type" => "refresh_token",
               "client_id" => client_id(),
               "refresh_token" => first["refresh_token"]
             })

    refute second["refresh_token"] == first["refresh_token"]

    assert {:error, %TamaOAuth.Error{code: :invalid_grant, stage: :refresh_replay}} =
             OAuth.exchange(%{
               "grant_type" => "refresh_token",
               "client_id" => client_id(),
               "refresh_token" => first["refresh_token"]
             })

    assert Repo.one!(Grant).current_state == "revoked"
  end

  test "introspection follows Actor and grant lifecycle" do
    scope = user_scope_fixture()
    %{code: code} = authorize(scope)
    assert {:ok, tokens} = exchange_code(code)

    credentials = ["Bearer test-tama-introspection-secret"]

    assert {:ok, %{"active" => true} = response} =
             OAuth.introspect(%{"token" => tokens["access_token"]}, credentials)

    assert response["sub"] == scope.actor.id
    assert response["grant_id"] == Repo.one!(Grant).id

    assert {:ok, :ok} =
             OAuth.revoke(%{
               "token" => tokens["access_token"],
               "client_id" => client_id(),
               "token_type_hint" => "access_token"
             })

    assert {:ok, %{"active" => false}} =
             OAuth.introspect(%{"token" => tokens["access_token"]}, credentials)
  end

  test "rejects the wrong resource and an inactive user Actor" do
    scope = user_scope_fixture()

    assert {:error, %TamaOAuth.Error{code: :invalid_target}} =
             OAuth.start_authorization(
               authorization_params(%{"resource" => "https://other.test/mcp"})
             )

    assert {:ok, handle} = OAuth.start_authorization(authorization_params())

    assert {:ok, _transition} =
             Memovee.Accounts.transition_actor(scope.actor, scope.actor, :deactivate)

    assert {:error, :invalid_consent} = OAuth.consent(scope, handle)
  end
end
