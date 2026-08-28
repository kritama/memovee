defmodule Memovee.OAuth.Client do
  @moduledoc "Application client trust, caching, and JWKS adapter."

  alias Memovee.OAuth
  alias Memovee.OAuth.Cache
  alias Memovee.OAuth.Client.Registration.Manager, as: RegistrationManager
  alias Memovee.OAuth.Tama.MCP
  alias TamaOAuth.ClientMetadata

  @cache_ttl_ms :timer.hours(1)

  def fetch(client_id) do
    if RegistrationManager.dynamic_client_id?(client_id),
      do: RegistrationManager.fetch(client_id),
      else: load(client_id, false)
  end

  def refresh(client_id) do
    if RegistrationManager.dynamic_client_id?(client_id),
      do: RegistrationManager.fetch(client_id),
      else: load(client_id, true)
  end

  def key(%ClientMetadata{client_id: client_id, jwks_uri: jwks_uri}, kid, algorithm)
      when is_binary(jwks_uri) do
    key = {:client_jwks, client_id, jwks_uri}

    with {:ok, jwks} <- cached_jwks(key, client_id, jwks_uri),
         {:ok, selected} <- TamaOAuth.JWKS.select(jwks, kid, algorithm, algorithms: [algorithm]) do
      {:ok, selected}
    else
      {:error, :temporarily_unavailable} -> {:error, :temporarily_unavailable}
      _ -> {:error, :invalid_client}
    end
  end

  def key(_metadata, _kid, _algorithm), do: {:error, :invalid_client}

  defp load(client_id, refresh?) do
    key = {:client_metadata, client_id}

    case {refresh?, Cache.get(key)} do
      {false, %ClientMetadata{} = metadata} -> {:ok, metadata}
      _ -> fetch_and_cache(key, client_id)
    end
  end

  defp fetch_and_cache(key, client_id) do
    with true <- MCP.allowed_client_id?(client_id),
         {:ok, metadata} <- fetch_metadata(client_id) do
      ttl = min((metadata.cache_ttl || div(@cache_ttl_ms, 1_000)) * 1_000, @cache_ttl_ms)
      :ok = Cache.put(key, metadata, max(ttl, 1_000))
      {:ok, metadata}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_client}
    end
  end

  defp fetch_metadata(client_id) do
    case OAuth.config(:pre_registered_clients, %{}) do
      %{^client_id => document} ->
        with {:ok, metadata} <- ClientMetadata.validate(document, client_id, metadata_options()) do
          digest =
            document
            |> :erlang.term_to_binary([:deterministic])
            |> TamaOAuth.Crypto.digest()

          {:ok, %{metadata | metadata_digest: digest, validated_url: client_id, cache_ttl: 3_600}}
        end

      _clients ->
        ClientMetadata.fetch(client_id, metadata_options())
    end
  end

  defp metadata_options do
    [
      allow_local?: OAuth.config(:allow_local_client_metadata, false),
      auth_methods: OAuth.config(:token_endpoint_auth_methods),
      signing_algorithms: OAuth.config(:token_endpoint_auth_signing_algorithms)
    ]
  end

  defp cached_jwks(key, client_id, jwks_uri) do
    case Cache.get(key) do
      nil ->
        with {:ok, jwks} <- TamaOAuth.JWKS.fetch(jwks_uri, client_id) do
          :ok = Cache.put(key, jwks, @cache_ttl_ms)
          {:ok, jwks}
        end

      jwks ->
        {:ok, jwks}
    end
  end
end
