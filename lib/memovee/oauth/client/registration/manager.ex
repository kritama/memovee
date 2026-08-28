defmodule Memovee.OAuth.Client.Registration.Manager do
  @moduledoc "Creates and resolves bounded dynamic public-client registrations."

  import Ecto.Query

  alias Memovee.OAuth
  alias Memovee.OAuth.Actor
  alias Memovee.OAuth.Client.Registration
  alias Memovee.Repo
  alias TamaOAuth.ClientMetadata

  def create(params) do
    Repo.transact(fn ->
      with {:ok, normalized} <-
             TamaOAuth.ClientRegistration.normalize(params,
               supported_scopes: ["mcp.message"]
             ),
           {:ok, actor} <- Actor.get(),
           {:ok, registration} <- persist(normalized),
           {:ok, registration} <- transition(registration, actor, "activate") do
        {:ok, response(registration)}
      end
    end)
  end

  def fetch(client_id) when is_binary(client_id) do
    case registration_id(client_id) do
      {:ok, id} -> fetch_registration(id, client_id)
      _error -> {:error, :invalid_client}
    end
  end

  def dynamic_client_id?(client_id), do: match?({:ok, _id}, registration_id(client_id))

  defp persist(normalized) do
    %Registration{}
    |> Registration.changeset(Map.from_struct(normalized))
    |> Repo.insert()
  end

  defp fetch_registration(id, client_id) do
    now = OAuth.now()
    touch_interval = OAuth.config(:registration_touch_interval_seconds)
    cutoff = DateTime.add(now, -touch_interval, :second)

    touch_query =
      from registration in Registration,
        where:
          registration.id == ^id and registration.current_state == "active" and
            (is_nil(registration.last_used_at) or registration.last_used_at <= ^cutoff),
        select: registration

    case Repo.update_all(touch_query, set: [last_used_at: now]) do
      {1, [registration]} ->
        {:ok, metadata(registration, client_id)}

      {0, []} ->
        Registration
        |> Repo.get_by(id: id, current_state: "active")
        |> registration_result(client_id)
    end
  end

  defp registration_result(nil, _client_id), do: {:error, :invalid_client}
  defp registration_result(registration, client_id), do: {:ok, metadata(registration, client_id)}

  defp transition(registration, actor, event_name) do
    case Eventful.Transit.perform(registration, actor, event_name) do
      {:ok, %{resource: transitioned}} -> {:ok, transitioned}
      error -> error
    end
  end

  defp response(registration) do
    %{
      "client_id" => client_id(registration.id),
      "client_id_issued_at" => DateTime.to_unix(registration.inserted_at),
      "application_type" => registration.application_type,
      "client_name" => registration.client_name,
      "client_uri" => registration.client_uri,
      "redirect_uris" => registration.redirect_uris,
      "grant_types" => registration.grant_types,
      "response_types" => registration.response_types,
      "token_endpoint_auth_method" => registration.token_endpoint_auth_method,
      "scope" => registration.scope
    }
  end

  defp metadata(registration, client_id) do
    %ClientMetadata{
      client_id: client_id,
      client_name: registration.client_name,
      client_uri: registration.client_uri,
      redirect_uris: registration.redirect_uris,
      grant_types: registration.grant_types,
      response_types: registration.response_types,
      token_endpoint_auth_methods_supported: [registration.token_endpoint_auth_method],
      token_endpoint_auth_signing_algorithms: [],
      metadata_digest: registration.metadata_digest,
      validated_url: client_id,
      registration_type: :dynamic,
      verified_client_metadata?: false,
      cache_ttl: 300
    }
  end

  defp client_id(id), do: OAuth.endpoint("/auth/registrations/#{id}")

  defp registration_id(client_id) do
    prefix = OAuth.endpoint("/auth/registrations/")

    with true <- String.starts_with?(client_id, prefix),
         id when id != "" <- String.replace_prefix(client_id, prefix, ""),
         {:ok, uuid} <- Ecto.UUID.cast(id),
         true <- id == uuid do
      {:ok, uuid}
    else
      _ -> {:error, :invalid_client}
    end
  end
end
