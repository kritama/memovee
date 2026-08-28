defmodule Memovee.OAuth.KeyProviderTest do
  use ExUnit.Case, async: true

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
end
