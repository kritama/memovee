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

Development uses a process-local asymmetric key. To configure the integration
in production, set its lifecycle mode explicitly to `prepared` or `enabled` and
provide these environment variables:

```text
MEMOVEE_TAMA_MCP_APP_MODE=prepared
MEMOVEE_OAUTH_ISSUER
MEMOVEE_TAMA_MCP_APP_RESOURCE
MEMOVEE_OAUTH_SIGNING_ALGORITHM
MEMOVEE_OAUTH_SIGNING_KEY_ID
MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY
MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS
MEMOVEE_TAMA_INTROSPECTION_CLIENT_ID
MEMOVEE_TAMA_INTROSPECTION_JWKS_URI
```

Use `prepared` while deploying and verifying the signing and introspection trust
configuration; this publishes the metadata and JWKS endpoints without allowing
new authorization grants or token issuance. Change the mode to `enabled` only
after Tama is ready to use the integration.

Existing production deployments upgrading from an earlier OAuth configuration
must add `MEMOVEE_TAMA_MCP_APP_MODE` before deploying this version. Set it to
`enabled` to preserve active authorization and token behavior, or to `prepared`
for a staged rollout. If the variable is omitted, production deliberately
defaults to `disabled`, and the OAuth metadata and JWKS endpoints return 404.
Use `disabled` only when intentionally shutting down the integration.

The private signing key is a JSON JWK. `MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS` is a
JSON array containing any previous public verification keys retained during a
rotation overlap. Tama authenticates introspection requests with
`private_key_jwt`; no signing secret is shared between the services.
For HTTPS resources, Memovee derives the one trusted private-network origin
from `MEMOVEE_TAMA_MCP_APP_RESOURCE`. This permits only that configured Tama
hostname to resolve to a private container-network address without disabling
DNS pinning, certificate verification, or hostname verification. Loopback HTTP
development remains governed separately by the local-development policy.

The Compose-managed local Tama profile builds the `development-local-ca`
Docker target. It extends the ordinary `development` target, installs only the
generated public `tama/tls/rootCA.pem` into Alpine's existing CA bundle, then
runs as the same unprivileged `memovee` user. The source, dependency, and build
mounts remain unchanged, so Phoenix code reload continues to work. Ordinary
development builds can still use `--target development` without generated
certificate material.

When Memovee runs behind a reverse proxy, the optional `MEMOVEE_TRUSTED_PROXIES`
variable is a comma-separated list of the exact IP addresses or CIDR ranges
allowed to supply `X-Forwarded-For`. When it is unset or empty, Memovee trusts no
forwarding headers and uses the direct socket peer address.

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
