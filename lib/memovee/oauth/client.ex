defmodule Memovee.OAuth.Client do
  @moduledoc "Application client trust, caching, and JWKS adapter."

  alias Memovee.Cache
  alias Memovee.OAuth

  alias Memovee.OAuth.Client.Registration.Manager, as: RegistrationManager
  alias Memovee.OAuth.JWKSCache
  alias Memovee.OAuth.Tama.MCP
  alias TamaOAuth.ClientMetadata

  @cache_ttl_ms :timer.hours(1)
  @failure_cooldown_ms :timer.seconds(30)
  @refresh_lock_retries 600
  @refresh_lock_retry_interval_ms 10
  @refresh_lock_timeout_ms :timer.seconds(10)

  def fetch(client_id, opts \\ []) do
    if RegistrationManager.dynamic_client_id?(client_id),
      do: RegistrationManager.fetch(client_id),
      else: load(client_id, false, opts)
  end

  def refresh(client_id, opts \\ []) do
    if RegistrationManager.dynamic_client_id?(client_id),
      do: RegistrationManager.fetch(client_id),
      else: load(client_id, true, opts)
  end

  def key(%ClientMetadata{client_id: client_id, jwks_uri: jwks_uri}, kid, algorithm)
      when is_binary(jwks_uri) do
    case JWKSCache.select(
           {:client_jwks, client_id, jwks_uri},
           jwks_uri,
           client_id,
           kid,
           algorithm,
           ttl_ms: @cache_ttl_ms
         ) do
      {:ok, selected} -> {:ok, selected}
      {:error, :temporarily_unavailable} -> {:error, :temporarily_unavailable}
      _ -> {:error, :invalid_client}
    end
  end

  def key(_metadata, _kid, _algorithm), do: {:error, :invalid_client}

  defp load(client_id, refresh?, opts) do
    if MCP.allowed_client_id?(client_id) do
      key = {:client_metadata, client_id}
      version_key = {__MODULE__, :version, key}
      failure_key = {__MODULE__, :failure, key}
      cached = Cache.get!(key)

      case {refresh?, cached} do
        {false, %ClientMetadata{} = metadata} ->
          {:ok, metadata}

        _ ->
          refresh_and_load(%{
            key: key,
            version_key: version_key,
            failure_key: failure_key,
            client_id: client_id,
            stale_version: Cache.get!(version_key),
            failure_cooldown_ms: Keyword.get(opts, :failure_cooldown_ms, @failure_cooldown_ms),
            metadata_loader: Keyword.get(opts, :metadata_loader, &fetch_metadata/1)
          })
      end
    else
      {:error, :invalid_client}
    end
  end

  defp refresh_and_load(context) do
    case Cache.transaction(
           fn -> load_refreshed_or_fetch(context) end,
           keys: [context.key],
           retries: @refresh_lock_retries,
           retry_interval: fn _attempt -> @refresh_lock_retry_interval_ms end,
           lock_timeout: @refresh_lock_timeout_ms
         ) do
      {:ok, result} -> result
      {:error, _reason} -> {:error, :temporarily_unavailable}
    end
  end

  defp load_refreshed_or_fetch(context) do
    metadata = Cache.get!(context.key)
    version = Cache.get!(context.version_key)

    cond do
      match?(%ClientMetadata{}, metadata) and version != context.stale_version ->
        {:ok, metadata}

      failure = Cache.get!(context.failure_key) ->
        failure

      true ->
        fetch_and_cache(context)
    end
  end

  defp fetch_and_cache(context) do
    case context.metadata_loader.(context.client_id) do
      {:ok, %ClientMetadata{} = metadata} ->
        ttl = min((metadata.cache_ttl || div(@cache_ttl_ms, 1_000)) * 1_000, @cache_ttl_ms)
        ttl = max(ttl, 1_000)

        :ok = Cache.put!(context.key, metadata, ttl: ttl)
        :ok = Cache.put!(context.version_key, make_ref(), ttl: ttl)
        :ok = Cache.delete!(context.failure_key)

        {:ok, metadata}

      {:error, reason} ->
        error = {:error, reason}
        :ok = Cache.put!(context.failure_key, error, ttl: context.failure_cooldown_ms)
        error

      _invalid ->
        error = {:error, :invalid_client}
        :ok = Cache.put!(context.failure_key, error, ttl: context.failure_cooldown_ms)
        error
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
end
