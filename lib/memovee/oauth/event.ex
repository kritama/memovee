defmodule Memovee.OAuth.Event do
  @moduledoc false

  require Logger

  @safe_keys ~w(client_id grant_id token_id actor_id resource scope failure_stage reason)a

  def emit(name, metadata \\ %{}) when is_atom(name) and is_map(metadata) do
    metadata = Map.take(metadata, @safe_keys)
    Logger.info("oauth_security_event event=#{name}", Map.to_list(metadata))
    :telemetry.execute([:memovee, :oauth, name], %{count: 1}, metadata)
  end
end
