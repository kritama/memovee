# Memovee

## Development

Memovee runs Elixir and Phoenix on the host and uses Docker Compose with OrbStack for PostgreSQL. The committed `.envrc` points Ecto to `postgres.kritama-memovee.orb.local`, so PostgreSQL does not need to publish or occupy a host port.

1. Allow direnv to load the development environment:

   ```sh
   direnv allow
   ```

2. Start PostgreSQL and wait for it to become healthy:

   ```sh
   docker compose up -d --wait postgres
   ```

3. Install dependencies and prepare the development database:

   ```sh
   mix setup
   ```

4. Start the Phoenix endpoint:

   ```sh
   mix phx.server
   ```

   To run the endpoint inside IEx instead, use `iex -S mix phx.server`.

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Tests

Tests use a separate `memovee_test` database on the same PostgreSQL service:

```sh
docker compose up -d --wait postgres
mix test
```

## OAuth authorization server

Memovee issues resource-bound OAuth access tokens for Tama's `/mcp/app`
protected resource. Shared OAuth protocol mechanics come from the released
`tama_oauth` Hex package; Memovee retains ownership of Actors, grants,
persistence, consent, signing-key custody, and HTTP endpoints.

Development uses a process-local asymmetric key. Production requires these
environment variables:

```text
MEMOVEE_OAUTH_ISSUER
MEMOVEE_TAMA_MCP_APP_RESOURCE
MEMOVEE_OAUTH_SIGNING_ALGORITHM
MEMOVEE_OAUTH_SIGNING_KEY_ID
MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY
MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS
MEMOVEE_TAMA_INTROSPECTION_CLIENT_ID
MEMOVEE_TAMA_INTROSPECTION_JWKS_URI
```

The private signing key is a JSON JWK. `MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS` is a
JSON array containing any previous public verification keys retained during a
rotation overlap. Tama authenticates introspection requests with
`private_key_jwt`; no signing secret is shared between the services.

## Database Lifecycle

Stop PostgreSQL without removing its data:

```sh
docker compose stop
```

Remove the containers and network while preserving database data:

```sh
docker compose down
```

To also delete all local development and test databases, run `docker compose down -v`.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
