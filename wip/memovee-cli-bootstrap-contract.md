# Memovee CLI Bootstrap Contract

Status: implementation in progress on `feature/tama-mcp-app-bootstrap`; live
cross-service acceptance and CLI orchestration remain outstanding.

This document is authoritative for Memovee-side bootstrap and configuration
changes. `oauth-authorization-server.md` remains authoritative for OAuth
behavior, persistence, consent, refresh rotation, revocation, and introspection
invariants. CLI orchestration lives in
`kritama/memovee-cli/wip/bootstrap-orchestration.md`.

## Goal

Make Memovee a versioned, machine-verifiable orchestration participant without
moving Memovee policy or secret custody into the CLI.

Memovee must support a safe preparation state in which it can:

- load and validate its access-token signing key;
- publish the corresponding public JWKS;
- validate Tama's `private_key_jwt` introspection identity;
- answer a controlled inactive-token introspection probe; and
- remain unavailable for end-user Tama authorization until activation.

The CLI coordinates these capabilities. Memovee remains authoritative for
configuration acceptance, cryptographic validation, OAuth policy, Actors,
grants, and token lifecycle.

## Ownership boundary

| Concern | Owner |
| --- | --- |
| OAuth authorization-server semantics | Memovee and `TamaOAuth` |
| Access-token signing private key | Memovee deployment |
| Tama introspection verification keys | Tama JWKS, consumed by Memovee |
| Canonical deployment topology | Memovee CLI plan |
| Environment rendering and atomic writes | Memovee CLI output adapter |
| Environment parsing and startup rejection | Memovee |
| Public metadata and JWKS truth | Running Memovee endpoint |
| Integration activation and rollback order | Memovee CLI orchestrator |

The CLI must never become a second OAuth implementation and must not receive
raw access tokens, refresh tokens, authorization codes, browser sessions, or
Memovee database credentials during ordinary orchestration.

## Integration lifecycle

Add an explicit deployment state:

```text
MEMOVEE_TAMA_MCP_APP_MODE=disabled|prepared|enabled
```

| Mode | Signing key and JWKS | Tama introspection authentication | User authorization and token issuance | Resource advertised |
| --- | --- | --- | --- | --- |
| `disabled` | No Tama integration key required | Rejected | Rejected | No |
| `prepared` | Key required; public JWK published | Enabled; unknown token returns inactive | Rejected | No |
| `enabled` | Key remains published | Enabled | Enabled | Yes |

Unknown modes fail startup before any Tama integration setting is read.
`disabled` must not require or parse the remaining integration variables.
`prepared` and `enabled` require the complete trust configuration.

Preparation is not a weaker authorization mode. It exists only to validate
bidirectional trust before user-facing activation and must not issue an access
or refresh token for the Tama resource.

The lifecycle gate has an exact wire contract. Disabled metadata and JWKS
return `404`. Disabled and prepared authorization and registration return
`503 temporarily_unavailable`; token exchange returns `400 invalid_grant`.
Disabled introspection returns `401 invalid_client`, and disabled revocation
returns `503 temporarily_unavailable`. Prepared and enabled introspection and
revocation are available subject to their ordinary authenticated request
contracts. The committed machine contract is authoritative for this matrix.

## Canonical topology

The local development default is:

```text
Memovee origin:                 http://127.0.0.1:4000
Tama origin:                    http://127.0.0.1:4001
Tama MCP App resource:          http://127.0.0.1:4001/mcp/app
Memovee authorization metadata: http://127.0.0.1:4000/.well-known/oauth-authorization-server
Memovee JWKS:                   http://127.0.0.1:4000/.well-known/jwks.json
Memovee introspection:          http://127.0.0.1:4000/auth/introspections
Tama public JWKS:               http://127.0.0.1:4001/.well-known/jwks.json
```

Production uses exact HTTPS equivalents. No identifier may be derived from an
incoming Host or forwarding header. The Tama resource remains the exact JWT
audience and must not be renamed to a generic Memovee API resource.

## Configuration contract

Prepared and enabled modes require:

```text
MEMOVEE_OAUTH_ISSUER
MEMOVEE_TAMA_MCP_APP_RESOURCE
MEMOVEE_OAUTH_SIGNING_ALGORITHM
MEMOVEE_OAUTH_SIGNING_KEY_ID
MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY
MEMOVEE_TAMA_INTROSPECTION_CLIENT_ID
MEMOVEE_TAMA_INTROSPECTION_JWKS_URI
```

The following rotation setting is optional in prepared and enabled modes and
defaults to an empty JSON array:

```text
MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS
```

Keep the current meanings:

- `MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY` is the current private JSON JWK owned
  only by Memovee and is limited to 65,536 encoded bytes;
- `MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS` contains public overlap keys retained
  during rotation, defaults to `[]`, and is limited to 2,097,152 encoded bytes;
- `MEMOVEE_TAMA_INTROSPECTION_CLIENT_ID` exactly matches Tama's assertion
  `iss` and `sub`;
- `MEMOVEE_TAMA_INTROSPECTION_JWKS_URI` points to Tama's public JWKS and never
  contains a private key; and
- the initial algorithm is exactly `RS256`, while Memovee retains its existing
  validated asymmetric allowlist.

Add a committed non-secret contract document such as:

```text
priv/contracts/tama-mcp-app-bootstrap-v1.json
```

It must include:

- schema and contract version;
- supported application version range;
- lifecycle states and state-dependent required variables;
- type, URI/path, algorithm, list, key, and size constraints;
- `x-sensitive` ownership metadata;
- public endpoint templates and local-loopback policy; and
- a compatibility identifier shared with Tama's contract.

Runtime tests must prove that this artifact and the actual parser do not drift.
The CLI may use it for planning, but successful startup and live metadata
remain final authority.

## Runtime configuration changes

The integration parser currently runs only inside the production block while
development relies on static defaults. Extract Tama integration parsing into a
focused application-owned configuration boundary exercised in development,
test, and production.

It must:

- apply development overrides when the lifecycle variable is present;
- retain safe standalone development defaults when it is absent;
- allow HTTP only for exact loopback hosts in development and test;
- require HTTPS in production;
- validate the issuer as an exact origin;
- validate the resource as the exact `/mcp/app` URI;
- validate the Tama JWKS endpoint and bind it to the configured trust domain;
- parse and validate JWK material before the endpoint starts;
- reject duplicate key IDs and private material in public overlap keys;
- avoid reading state-dependent variables in disabled mode; and
- expose normalized configuration using ordinary Elixir values.

Do not move configuration parsing into `memovee-cli`. Memovee independently
rejects incomplete or inconsistent CLI output.

## Development environment ownership

The committed `.envrc` remains repository-owned and loads one optional,
root-ignored integration fragment by fixed relative path:

```text
.memovee.integration.env
```

Memovee CLI is the only writer for this fragment. It is created with mode
`0600`, ignored before the first write, rejected if already tracked, checked
against symlinked ancestors, and updated atomically. The committed `.envrc`
must not embed generated keys or be rewritten on every CLI run.

The fragment contains only Memovee-owned integration values. Tama's private
introspection key must never be copied into it.

## Prepared-mode behavior

In prepared mode:

- `GET /.well-known/jwks.json` publishes the current Memovee OAuth public key;
- `POST /auth/introspections` authenticates Tama with `private_key_jwt`;
- a valid Tama assertion with a deliberately invalid access token returns HTTP
  success with `active: false`;
- authorization-server metadata does not advertise the Tama resource;
- authorization start, consent approval, code exchange, and refresh reject the
  Tama resource through the normal OAuth error contract; and
- no bearer introspection compatibility secret is introduced.

The controlled inactive-token request is the CLI readiness probe. It proves
that Memovee fetched Tama's JWKS, selected the assertion `kid`, validated the
assertion, and reached token introspection without requiring a real user token.

## Enabled-mode behavior

Activation changes only availability. In enabled mode:

- authorization-server metadata advertises the exact Tama resource;
- authorization requests may proceed through existing authentication and
  consent;
- token and refresh endpoints keep all existing binding and rotation
  invariants;
- introspection remains mandatory and authenticated; and
- access-token `sub` remains the approving Memovee Actor UUID.

Changing mode requires an application restart. Runtime mutation of issuer,
resource, endpoints, algorithms, or keys is out of scope.

## Public verification contract

The CLI uses existing protocol endpoints; do not add a secret-bearing health
endpoint.

Verification must:

1. fetch authorization-server metadata with strict time and size bounds;
2. confirm exact issuer and endpoint origins;
3. confirm the resource is absent in prepared and present in enabled;
4. fetch JWKS and select the configured signing `kid` and algorithm;
5. submit the authenticated inactive-token introspection probe;
6. reject redirects, wrong content types, oversized responses, or credential
   material in errors; and
7. record only public identifiers and safe result enums.

Authorization-server metadata uses `Cache-Control: no-store` in every lifecycle
mode so activation and rollback cannot be hidden by a previously cached
prepared, enabled, or disabled response. Public JWKS remains cacheable for its
bounded rotation window.

## Activation and rollback order

Activation is:

1. Memovee prepared;
2. Tama prepared;
3. verify both public keys and authenticated introspection;
4. Tama enabled;
5. verify Tama metadata and unauthenticated challenge;
6. Memovee enabled; and
7. perform real MCP authorization and `message` acceptance.

Rollback reverses exposure:

1. Memovee returns to prepared, stopping advertisement and new issuance;
2. Tama returns to prepared, removing `/mcp/app` while retaining trust
   material;
3. retain public overlap keys for all token, assertion, cache, skew, and
   deployment windows; and
4. move to disabled only when no lifecycle requires the prepared keys.

Never roll back to unauthenticated introspection, shared symmetric keys, or
acceptance without current Actor/grant/access-reference checks.

## Tests

Add focused tests for:

- lifecycle parsing and unknown states;
- minimal disabled startup without integration variables;
- every missing prepared/enabled variable;
- loopback development overrides and production HTTPS enforcement;
- private/public JWK validation, duplicate `kid`, and overlap lists;
- resource omission in prepared and inclusion in enabled metadata;
- authorization and token rejection in prepared;
- valid Tama assertion plus inactive token in prepared;
- unknown `kid`, invalid signature, replay, timeout, and JWKS rotation;
- exact resource and introspection-client agreement fixtures shared with Tama;
- fragment ignore, permissions, idempotence, drift, and symlink safety at the
  CLI integration layer; and
- no raw key, token, assertion, or setup credential in logs or errors.

Phoenix parameter filtering covers access and refresh tokens, authorization
codes, client assertions and secrets, and password fields. Authorization
headers are consumed only for client authentication and must never be added to
request or security-event logs.

Run focused OAuth and endpoint tests, the full suite, `mix precommit`, Dialyzer
where configured, and `git diff --check`.

## Implementation phases

### Phase 1: contract and lifecycle

- Add the lifecycle state and committed non-secret contract.
- Refactor configuration parsing for development and production overrides.
- Add parser/contract consistency tests.

### Phase 2: prepared state

- Gate resource advertisement and authorization by state.
- Keep signing-key publication and authenticated inactive-token introspection
  available in prepared.
- Add readiness and negative security tests.

### Phase 3: source-development integration

- Add the optional integration-fragment include to committed `.envrc`.
- Add root-anchored ignore rules before any generated secret exists.
- Add a local fixture using Memovee 4000 and Tama 4001.

### Phase 4: cross-repository acceptance

- Consume the same contract version as Tama and Memovee CLI.
- Exercise `prepared -> enabled -> prepared` across live services.
- Complete authorization, refresh, revocation, Actor deactivation, and message
  acceptance without exposing credentials.

## Acceptance criteria

Memovee is ready for CLI orchestration when:

- all lifecycle states have explicit fail-closed semantics;
- development and production use the same normalized configuration model;
- the non-secret contract is versioned and checked against runtime behavior;
- Memovee's private signing key never leaves its owner-specific output;
- prepared publishes JWKS and authenticates Tama without authorizing users;
- enabled alone advertises and issues for the exact Tama resource;
- local Memovee and Tama defaults agree on ports and identifiers;
- readiness is proven through metadata, JWKS, and authenticated inactive
  introspection;
- rollback removes exposure before trust material; and
- `mix precommit` and cross-service acceptance pass.

## Out of scope

- implementing CLI commands in the Phoenix repository;
- storing CLI state in Memovee's database;
- forwarding Tama MCP bearer tokens to Memovee APIs;
- generating or storing Tama's introspection private key;
- provisioning Tama graphs from Memovee controllers;
- silently mutating production secret managers; and
- weakening OAuth, refresh, revocation, or introspection for setup convenience.
