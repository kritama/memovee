credential = System.fetch_env!("MEMOVEE_MEMORY_TAMA_API_CREDENTIAL")
actor_id = System.fetch_env!("MEMOVEE_MEMORY_TAMA_ACTOR_ID")

with [client_id, secret] <- String.split(credential, ".", parts: 2),
     {:ok, actor} <- Memovee.Accounts.verify_api_token(client_id, secret),
     true <- actor.id == actor_id do
  IO.puts("MEMORY_ACTOR_READY")
else
  _ ->
    IO.puts("Configured memory service Actor/API credential is inactive or does not match")
    System.halt(1)
end
