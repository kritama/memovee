defmodule Memovee.OAuth.KeyProvider do
  @moduledoc "Application-owned OAuth signing-key custody."

  @behaviour TamaOAuth.KeyProvider

  alias Memovee.OAuth

  @cache_key {__MODULE__, :development_key}

  @impl true
  def signing_key do
    with {:ok, keys} <- configured_or_development_keys(),
         kid <- OAuth.config(:signing_key_id),
         algorithm <- OAuth.config(:signing_algorithm, "RS256"),
         %{} = key <- Enum.find(keys, &key_id?(&1, kid)) do
      {:ok, %{kid: kid, algorithm: algorithm, key: key}}
    else
      _ -> {:error, :signing_key_unavailable}
    end
  end

  @impl true
  def verification_keys, do: configured_or_development_keys()

  def public_jwks do
    with {:ok, keys} <- verification_keys() do
      TamaOAuth.JWKS.public_document(keys)
    end
  end

  def validate_signing_key(key, algorithm, kid) do
    claims = %{
      "iss" => "https://issuer.invalid",
      "sub" => "signing-key-check",
      "aud" => "https://resource.invalid",
      "client_id" => "signing-key-check",
      "scope" => "signing-key-check",
      "jti" => "signing-key-check"
    }

    case TamaOAuth.JWT.mint_access_token(claims, key,
           algorithm: algorithm,
           kid: kid,
           now: 0,
           ttl: 1
         ) do
      {:ok, _token, _claims} -> :ok
      {:error, _error} -> {:error, :invalid_signing_key}
    end
  end

  defp configured_or_development_keys do
    case OAuth.config(:signing_keys, []) do
      keys when is_list(keys) and keys != [] -> {:ok, Enum.uniq_by(keys, &key_id/1)}
      [] -> development_keys()
    end
  end

  defp development_keys do
    if Application.get_env(:memovee, :environment, :prod) == :prod do
      {:error, :signing_key_unavailable}
    else
      {:ok, [:persistent_term.get(@cache_key, nil) || generate_development_key()]}
    end
  end

  defp generate_development_key do
    kid = OAuth.config(:signing_key_id)
    jwk = JOSE.JWK.generate_key({:rsa, 2_048})
    {_fields, key} = JOSE.JWK.to_map(jwk)
    key = Map.merge(key, %{"kid" => kid, "alg" => "RS256", "use" => "sig"})
    :persistent_term.put(@cache_key, key)
    key
  end

  defp key_id?(%{"kid" => kid}, kid), do: true
  defp key_id?(_key, _kid), do: false

  defp key_id(%{"kid" => kid}), do: kid
  defp key_id(key), do: key
end
