defmodule Memovee.OAuth.KeyProviderTest do
  use ExUnit.Case, async: false

  alias Memovee.OAuth
  alias Memovee.OAuth.KeyProvider

  test "validates that a configured signing key contains private material" do
    assert {:ok, signing} = KeyProvider.signing_key()

    assert :ok =
             KeyProvider.validate_signing_key(signing.key, signing.algorithm, signing.kid)

    {_fields, public_key} =
      signing.key
      |> JOSE.JWK.from_map()
      |> JOSE.JWK.to_public_map()

    public_key =
      Map.merge(public_key, %{
        "kid" => signing.kid,
        "alg" => signing.algorithm,
        "use" => "sig"
      })

    assert {:error, :invalid_signing_key} =
             KeyProvider.validate_signing_key(public_key, signing.algorithm, signing.kid)
  end

  test "publishes eligible public overlap keys during rotation" do
    {:ok, overlap_private} =
      TamaOAuth.SigningKey.generate({:rsa, 2_048},
        algorithm: "RS256",
        algorithms: ["RS256"],
        kid: "memovee-overlap-rs256-1"
      )

    {:ok, %{"keys" => [overlap_public]}} =
      TamaOAuth.JWKS.public_document([overlap_private])

    replace_public_signing_keys([overlap_public])

    assert {:ok, %{"keys" => keys}} = KeyProvider.public_jwks()

    assert Enum.map(keys, & &1["kid"]) |> Enum.sort() ==
             ["memovee-oauth-test-rs256-1", "memovee-overlap-rs256-1"]
  end

  test "rejects duplicate key IDs and private overlap material" do
    assert {:ok, signing} = KeyProvider.signing_key()
    assert {:ok, %{"keys" => [current_public]}} = KeyProvider.public_jwks()

    replace_public_signing_keys([current_public])
    assert {:error, :invalid_jwks} = KeyProvider.public_jwks()

    replace_public_signing_keys([
      Map.put(signing.key, "kid", "memovee-private-overlap-rs256-1")
    ])

    assert {:error, :signing_key_unavailable} = KeyProvider.public_jwks()
  end

  defp replace_public_signing_keys(keys) do
    original = Application.fetch_env!(:memovee, OAuth)

    unless Process.get({__MODULE__, :restore_registered}) do
      Process.put({__MODULE__, :restore_registered}, true)
      on_exit(fn -> Application.put_env(:memovee, OAuth, original) end)
    end

    current = Application.fetch_env!(:memovee, OAuth)
    Application.put_env(:memovee, OAuth, Keyword.put(current, :public_signing_keys, keys))
  end
end
