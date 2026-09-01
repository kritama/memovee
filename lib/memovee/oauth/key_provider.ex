defmodule Memovee.OAuth.KeyProvider do
  @moduledoc "Application-owned OAuth signing-key custody."

  @behaviour TamaOAuth.KeyProvider

  alias Memovee.OAuth
  alias Memovee.OAuth.Tama.MCP
  alias TamaOAuth.{JWKS, SigningKey}

  @impl true
  def signing_key do
    if MCP.configured?() do
      algorithm = OAuth.config(:signing_algorithm)
      kid = OAuth.config(:signing_key_id)

      case SigningKey.load(OAuth.config(:signing_key), signing_key_options(algorithm, kid)) do
        {:ok, key} -> {:ok, %{algorithm: algorithm, kid: kid, key: key}}
        _error -> {:error, :signing_key_unavailable}
      end
    else
      {:error, :signing_key_unavailable}
    end
  end

  @impl true
  def verification_keys do
    with {:ok, document} <- public_jwks() do
      {:ok, document["keys"]}
    end
  end

  def public_jwks do
    algorithm = OAuth.config(:signing_algorithm, "RS256")
    overlap_keys = OAuth.config(:public_signing_keys, [])

    with true <- MCP.configured?(),
         {:ok, %{key: key}} <- signing_key(),
         :ok <- validate_overlap_keys(overlap_keys, algorithm) do
      JWKS.public_document([key | overlap_keys])
    else
      _error -> {:error, :signing_key_unavailable}
    end
  end

  def validate_config! do
    if MCP.configured?() do
      case public_jwks() do
        {:ok, _document} -> :ok
        {:error, _reason} -> raise "invalid Memovee OAuth asymmetric signing-key configuration"
      end
    else
      :ok
    end
  end

  def validate_signing_key(key, algorithm, kid) do
    case SigningKey.load(key, signing_key_options(algorithm, kid)) do
      {:ok, _key} -> :ok
      {:error, _error} -> {:error, :invalid_signing_key}
    end
  end

  defp signing_key_options(algorithm, kid) do
    [
      algorithm: algorithm,
      algorithms: [algorithm],
      kid: kid,
      stage: :oauth_signing_key
    ]
  end

  defp validate_overlap_keys([], _algorithm), do: :ok

  defp validate_overlap_keys(keys, algorithm) when is_list(keys) do
    with {:ok, set} <- JWKS.validate(%{"keys" => keys}),
         true <- Enum.all?(keys, &eligible_overlap_key?(set, &1, algorithm)) do
      :ok
    else
      _error -> {:error, :invalid_jwks}
    end
  end

  defp validate_overlap_keys(_keys, _algorithm), do: {:error, :invalid_jwks}

  defp eligible_overlap_key?(set, key, algorithm) do
    match?({:ok, _key}, JWKS.select(set, key["kid"], algorithm, algorithms: [algorithm]))
  end
end
