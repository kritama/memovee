defmodule Memovee.OAuth.JWKSCache do
  @moduledoc "Selects cached verification keys and refreshes stale JWKS after key rotation."

  alias Memovee.Cache

  @refresh_cooldown_ms :timer.seconds(30)
  @refresh_lock_retries 600
  @refresh_lock_retry_interval_ms 10
  @refresh_lock_timeout_ms :timer.seconds(10)

  def select(cache_key, jwks_uri, origin, kid, algorithm, opts \\ []) do
    context = %{
      cache_key: cache_key,
      refresh_key: {__MODULE__, :refresh, cache_key},
      jwks_uri: jwks_uri,
      origin: origin,
      kid: kid,
      algorithm: algorithm,
      ttl_ms: Keyword.fetch!(opts, :ttl_ms),
      refresh_cooldown_ms: Keyword.get(opts, :refresh_cooldown_ms, @refresh_cooldown_ms),
      fetcher: Keyword.get(opts, :fetcher, &TamaOAuth.JWKS.fetch/2)
    }

    case Cache.get!(cache_key) do
      nil ->
        refresh_and_select(context, nil)

      jwks ->
        case select_key(jwks, context) do
          {:error, :unknown_kid} -> refresh_and_select(context, jwks)
          result -> result
        end
    end
  end

  defp refresh_and_select(context, stale_jwks) do
    case Cache.transaction(
           fn -> select_refreshed_or_fetch(context, stale_jwks) end,
           keys: [context.cache_key],
           retries: @refresh_lock_retries,
           retry_interval: fn _attempt -> @refresh_lock_retry_interval_ms end,
           lock_timeout: @refresh_lock_timeout_ms
         ) do
      {:ok, result} -> result
      {:error, _reason} -> {:error, :temporarily_unavailable}
    end
  end

  defp select_refreshed_or_fetch(context, stale_jwks) do
    jwks = Cache.get!(context.cache_key)
    refresh_status = Cache.get!(context.refresh_key)

    if not is_nil(jwks) and jwks != stale_jwks do
      case select_key(jwks, context) do
        {:error, :unknown_kid} -> reuse_or_fetch(context, jwks, refresh_status)
        result -> result
      end
    else
      reuse_or_fetch(context, jwks, refresh_status)
    end
  end

  defp reuse_or_fetch(context, jwks, refresh_status) do
    case refresh_status do
      :refreshed ->
        if is_nil(jwks), do: fetch_and_select(context), else: select_key(jwks, context)

      {:error, _reason} = error ->
        error

      nil ->
        fetch_and_select(context)
    end
  end

  defp fetch_and_select(context) do
    case context.fetcher.(context.jwks_uri, context.origin) do
      {:ok, jwks} ->
        :ok = Cache.put!(context.cache_key, jwks, ttl: context.ttl_ms)

        :ok =
          Cache.put!(context.refresh_key, :refreshed, ttl: context.refresh_cooldown_ms)

        select_key(jwks, context)

      {:error, _reason} = error ->
        :ok = Cache.put!(context.refresh_key, error, ttl: context.refresh_cooldown_ms)
        error
    end
  end

  defp select_key(jwks, context) do
    TamaOAuth.JWKS.select(jwks, context.kid, context.algorithm, algorithms: [context.algorithm])
  end
end
