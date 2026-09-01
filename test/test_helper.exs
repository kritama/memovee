ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Memovee.Repo, :manual)

{:ok, test_tama_introspection_signing_key} =
  TamaOAuth.SigningKey.generate({:rsa, 2_048},
    algorithm: "RS256",
    algorithms: ["RS256"],
    kid: "tama-test-introspection-rs256-1",
    stage: :test_introspection_key
  )

Application.put_env(
  :memovee,
  :test_tama_introspection_signing_key,
  test_tama_introspection_signing_key
)
