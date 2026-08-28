defmodule Memovee.OAuthFixtures do
  @moduledoc false

  alias Memovee.OAuth

  def client_id, do: "http://127.0.0.1/client.json"
  def redirect_uri, do: "http://127.0.0.1/callback"
  def verifier, do: String.duplicate("v", 43)

  def authorization_params(overrides \\ %{}) do
    {:ok, challenge} = TamaOAuth.PKCE.challenge(verifier())

    Map.merge(
      %{
        "response_type" => "code",
        "client_id" => client_id(),
        "redirect_uri" => redirect_uri(),
        "resource" => OAuth.resource(),
        "scope" => "mcp.message",
        "state" => "opaque-client-state",
        "code_challenge" => challenge,
        "code_challenge_method" => "S256"
      },
      overrides
    )
  end

  def authorize(scope) do
    {:ok, handle} = OAuth.start_authorization(authorization_params())
    {:ok, redirect_uri} = OAuth.approve(scope, handle)
    query = redirect_uri |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    %{handle: handle, code: Map.fetch!(query, "code"), redirect_uri: redirect_uri}
  end

  def exchange_code(code) do
    OAuth.exchange(%{
      "grant_type" => "authorization_code",
      "client_id" => client_id(),
      "code" => code,
      "redirect_uri" => redirect_uri(),
      "code_verifier" => verifier()
    })
  end
end
