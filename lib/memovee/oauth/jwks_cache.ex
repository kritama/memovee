defmodule Memovee.OAuth.JWKSCache do
  @moduledoc "Selects cached verification keys and refreshes stale JWKS after key rotation."

  alias Memovee.OAuth.Cache

  def select(cache_key, jwks_uri, origin, kid, algorithm, opts \\ []) do
    ttl_ms = Keyword.fetch!(opts, :ttl_ms)
    fetcher = Keyword.get(opts, :fetcher, &TamaOAuth.JWKS.fetch/2)

    case Cache.get(cache_key) do
      nil ->
        refresh_and_select(cache_key, nil, jwks_uri, origin, kid, algorithm, ttl_ms, fetcher)

      jwks ->
        case select_key(jwks, kid, algorithm) do
          {:error, :unknown_kid} ->
            refresh_and_select(
              cache_key,
              jwks,
              jwks_uri,
              origin,
              kid,
              algorithm,
              ttl_ms,
              fetcher
            )

          result ->
            result
        end
    end
  end

  defp refresh_and_select(
         cache_key,
         stale_jwks,
         jwks_uri,
         origin,
         kid,
         algorithm,
         ttl_ms,
         fetcher
       ) do
    case :global.trans(
           {__MODULE__, cache_key},
           fn ->
             select_refreshed_or_fetch(
               cache_key,
               stale_jwks,
               jwks_uri,
               origin,
               kid,
               algorithm,
               ttl_ms,
               fetcher
             )
           end,
           [node()]
         ) do
      {:aborted, _reason} -> {:error, :temporarily_unavailable}
      result -> result
    end
  end

  defp select_refreshed_or_fetch(
         cache_key,
         stale_jwks,
         jwks_uri,
         origin,
         kid,
         algorithm,
         ttl_ms,
         fetcher
       ) do
    case Cache.get(cache_key) do
      jwks when not is_nil(jwks) and jwks != stale_jwks ->
        case select_key(jwks, kid, algorithm) do
          {:error, :unknown_kid} ->
            fetch_and_select(cache_key, jwks_uri, origin, kid, algorithm, ttl_ms, fetcher)

          result ->
            result
        end

      _stale_or_missing ->
        fetch_and_select(cache_key, jwks_uri, origin, kid, algorithm, ttl_ms, fetcher)
    end
  end

  defp fetch_and_select(cache_key, jwks_uri, origin, kid, algorithm, ttl_ms, fetcher) do
    with {:ok, jwks} <- fetcher.(jwks_uri, origin),
         :ok <- Cache.put(cache_key, jwks, ttl_ms) do
      select_key(jwks, kid, algorithm)
    end
  end

  defp select_key(jwks, kid, algorithm) do
    TamaOAuth.JWKS.select(jwks, kid, algorithm, algorithms: [algorithm])
  end
end
