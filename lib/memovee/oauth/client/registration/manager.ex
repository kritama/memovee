defmodule Memovee.OAuth.Client.Registration.Manager do
  @moduledoc "Creates and resolves bounded dynamic public-client registrations."

  import Ecto.Query

  alias Memovee.OAuth
  alias Memovee.OAuth.Actor
  alias Memovee.OAuth.Client.Registration
  alias Memovee.OAuth.Client.Registration.Event, as: RegistrationEvent
  alias Memovee.OAuth.Grant.Manager, as: GrantManager
  alias Memovee.OAuth.Request.Manager, as: RequestManager
  alias Memovee.OAuth.Tama.MCP
  alias Memovee.Repo
  alias TamaOAuth.ClientMetadata

  def create(params) do
    Repo.transact(fn ->
      with {:ok, normalized} <-
             TamaOAuth.ClientRegistration.normalize(params,
               supported_scopes: MCP.supported_scopes()
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

  def cleanup_abandoned(now) do
    cutoff = DateTime.add(now, -OAuth.config(:registration_abandonment_seconds), :second)
    batch_size = OAuth.config(:registration_cleanup_batch_size)
    registration_ids = cleanup_candidates(cutoff, now, batch_size)

    Enum.each(
      registration_ids,
      &delete_abandoned_registration(&1, cutoff, now)
    )

    length(registration_ids) == batch_size
  end

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

  defp cleanup_candidates(cutoff, now, batch_size) do
    client_id_prefix = OAuth.endpoint("/auth/registrations/")
    active_requests = RequestManager.active_client_ids_query(now)
    active_grants = GrantManager.active_client_ids_query()

    from(registration in Registration,
      left_join: request in subquery(active_requests),
      on: request.client_id == fragment("? || ?::text", ^client_id_prefix, registration.id),
      left_join: grant in subquery(active_grants),
      on: grant.client_id == fragment("? || ?::text", ^client_id_prefix, registration.id),
      where:
        fragment(
          "COALESCE(?, ?) <= ?",
          registration.last_used_at,
          registration.inserted_at,
          ^cutoff
        ) and is_nil(request.client_id) and is_nil(grant.client_id),
      order_by: [
        asc: registration.last_used_at,
        asc: registration.inserted_at,
        asc: registration.id
      ],
      limit: ^batch_size,
      select: registration.id
    )
    |> Repo.all()
  end

  defp delete_abandoned_registration(registration_id, cutoff, now) do
    registration =
      Registration
      |> where([registration], registration.id == ^registration_id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    if abandoned_registration?(registration, cutoff) and
         not registration_in_use?(registration, now) do
      Repo.delete_all(
        from(event in RegistrationEvent,
          where: event.oauth_client_registration_id == ^registration.id
        )
      )

      Repo.delete!(registration)
    end
  end

  defp abandoned_registration?(nil, _cutoff), do: false

  defp abandoned_registration?(registration, cutoff) do
    last_used_at = registration.last_used_at || registration.inserted_at
    DateTime.compare(last_used_at, cutoff) in [:lt, :eq]
  end

  defp registration_in_use?(registration, now) do
    registration.id
    |> client_id()
    |> then(fn client_id ->
      RequestManager.active_for_client?(client_id, now) or
        GrantManager.active_for_client?(client_id)
    end)
  end

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
