defmodule Memovee.OAuth.AuthorizationTest do
  use Memovee.DataCase, async: false

  import Memovee.AccountsFixtures
  import Memovee.OAuthFixtures

  alias Memovee.Accounts.Token
  alias Memovee.OAuth
  alias Memovee.OAuth.{Cache, Code, Grant, KeyProvider, Request}
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

  test "preserves repeated callback query pairs while replacing OAuth response parameters" do
    scope = user_scope_fixture()

    callback_uri =
      redirect_uri() <> "?aud=first%20audience&aud=second+audience&state=stale&code=stale"

    register_callback(callback_uri)

    assert {:ok, handle} =
             OAuth.start_authorization(authorization_params(%{"redirect_uri" => callback_uri}))

    assert {:ok, redirect_uri} = OAuth.approve(scope, handle)
    query = redirect_uri |> URI.parse() |> Map.fetch!(:query)
    pairs = query |> URI.query_decoder() |> Enum.to_list()

    assert String.starts_with?(
             query,
             "aud=first%20audience&aud=second+audience&"
           )

    assert Enum.filter(pairs, &match?({"aud", _value}, &1)) == [
             {"aud", "first audience"},
             {"aud", "second audience"}
           ]

    assert [{"state", "opaque-client-state"}] = Enum.filter(pairs, &match?({"state", _}, &1))
    assert [{"code", code}] = Enum.filter(pairs, &match?({"code", _}, &1))
    assert code != "stale"
    assert [{"iss", issuer}] = Enum.filter(pairs, &match?({"iss", _}, &1))
    assert issuer == OAuth.issuer()
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

  test "approval and refresh exchange acquire Actor and grant locks in the same order" do
    scope = user_scope_fixture()
    %{code: code} = authorize(scope)
    assert {:ok, tokens} = exchange_code(code)
    assert {:ok, handle} = OAuth.start_authorization(authorization_params())

    operations = [
      fn -> OAuth.approve(scope, handle) end,
      fn ->
        OAuth.exchange(%{
          "grant_type" => "refresh_token",
          "client_id" => client_id(),
          "refresh_token" => tokens["refresh_token"]
        })
      end
    ]

    results =
      operations
      |> Task.async_stream(fn operation -> operation.() end, timeout: :infinity)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, _result}, &1))
    assert Repo.one!(Grant).current_state == "active"
  end

  test "approval and revocation acquire Actor and grant locks in the same order" do
    scope = user_scope_fixture()
    %{code: code} = authorize(scope)
    assert {:ok, tokens} = exchange_code(code)
    assert {:ok, handle} = OAuth.start_authorization(authorization_params())

    operations = [
      fn -> OAuth.approve(scope, handle) end,
      fn ->
        OAuth.revoke(%{
          "token" => tokens["access_token"],
          "client_id" => client_id(),
          "token_type_hint" => "access_token"
        })
      end
    ]

    results =
      operations
      |> Task.async_stream(fn operation -> operation.() end, timeout: :infinity)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, _result}, &1))
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

  test "rejects pending requests after the configured resource changes" do
    scope = user_scope_fixture()
    assert {:ok, handle} = OAuth.start_authorization(authorization_params())

    replace_resource("https://tama.example/mcp/app-v2")

    assert {:error, :invalid_consent} = OAuth.consent(scope, handle)
    assert {:error, :authorization_policy_changed} = OAuth.approve(scope, handle)
    refute Repo.exists?(Code)
    refute Repo.exists?(Grant)
  end

  test "rejects authorization codes issued for a retired resource" do
    scope = user_scope_fixture()
    %{code: code} = authorize(scope)

    replace_resource("https://tama.example/mcp/app-v2")

    assert {:error, %TamaOAuth.Error{code: :invalid_grant}} = exchange_code(code)
  end

  test "rejects authorization codes and refresh tokens for a retired scope" do
    scope = user_scope_fixture()
    %{code: code} = authorize(scope)

    Repo.update_all(Grant, set: [scope: "retired.scope"])
    Repo.update_all(Code, set: [scope: "retired.scope"])

    assert {:error, %TamaOAuth.Error{code: :invalid_grant}} = exchange_code(code)

    Repo.update_all(Grant, set: [scope: "mcp.message"])
    Repo.update_all(Code, set: [scope: "mcp.message"])
    assert {:ok, tokens} = exchange_code(code)
    Repo.update_all(Grant, set: [scope: "retired.scope"])

    assert {:error, %TamaOAuth.Error{code: :invalid_grant}} =
             OAuth.exchange(%{
               "grant_type" => "refresh_token",
               "client_id" => client_id(),
               "refresh_token" => tokens["refresh_token"]
             })
  end

  test "rejects pending requests whose scope is no longer supported" do
    scope = user_scope_fixture()
    assert {:ok, handle} = OAuth.start_authorization(authorization_params())
    Repo.update_all(Request, set: [scope: "retired.scope"])

    assert {:error, :invalid_consent} = OAuth.consent(scope, handle)
    assert {:error, :authorization_policy_changed} = OAuth.approve(scope, handle)
    refute Repo.exists?(Code)
    refute Repo.exists?(Grant)
  end

  defp replace_resource(resource) do
    original_config = Application.fetch_env!(:memovee, OAuth)
    on_exit(fn -> Application.put_env(:memovee, OAuth, original_config) end)
    Application.put_env(:memovee, OAuth, Keyword.put(original_config, :resource, resource))
  end

  defp register_callback(callback_uri) do
    original_config = Application.fetch_env!(:memovee, OAuth)
    original_clients = Keyword.fetch!(original_config, :pre_registered_clients)

    client =
      original_clients |> Map.fetch!(client_id()) |> Map.put("redirect_uris", [callback_uri])

    updated_config =
      Keyword.put(
        original_config,
        :pre_registered_clients,
        Map.put(original_clients, client_id(), client)
      )

    Cache.delete({:client_metadata, client_id()})
    Application.put_env(:memovee, OAuth, updated_config)

    on_exit(fn ->
      Application.put_env(:memovee, OAuth, original_config)
      Cache.delete({:client_metadata, client_id()})
    end)
  end
end
