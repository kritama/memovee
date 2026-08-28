# Memovee OAuth Authorization Server for Tama MCP App

Status: Memovee authorization server implemented on
`feature/oauth-authorization-server`; Tama protected-resource integration and
live MCP acceptance remain pending.

This document defines the coordinated work required to authorize MCP clients
for Tama's application-facing MCP resource. Memovee remains the OAuth
authorization server, Tama remains the protected resource, and the shared
framework-neutral mechanics live in the separate `tama_oauth` Hex package. It
does not implement Tama's `/mcp/app` server or its `message` tool.

## Goal

Allow a supported MCP client to connect to Tama at:

```text
https://<tama-host>/mcp/app
```

and authorize through Memovee as an existing Memovee user. After consent, the
MCP client receives a short-lived access token issued by Memovee and intended
only for Tama's exact `/mcp/app` resource. Tama validates that token and obtains
the Memovee user Actor UUID from its authenticated subject.

The first application-facing MCP resource has one tool and one capability:

```text
message({model, body})
scope: mcp.message
```

The client never supplies an `actor_id` tool argument. Tama derives the Actor
UUID exclusively from the validated OAuth principal and injects it into the
message execution context.

## Architecture

The OAuth roles are:

| OAuth role | Component |
| --- | --- |
| Resource owner | Authenticated Memovee user |
| Authorization server | Memovee |
| OAuth client | MCP host such as Codex or ChatGPT |
| Protected resource | Tama `/mcp/app` |
| Token issuer | Memovee |
| Token consumer | Tama |
| Shared protocol library | `TamaOAuth` (`:tama_oauth`) |

Memovee and Tama retain separate APIs. A token issued by this flow authorizes
only access to Tama's `/mcp/app`; it is not a bearer credential for Memovee's
API or for any other Tama resource.

### Shared package boundary

The shared package is maintained at:

```text
/home/zacksiri/Work/_kritama/tama-oauth
```

Its naming is:

```text
repository: tama-oauth
Mix application: :tama_oauth
Hex package: tama_oauth
root namespace: TamaOAuth
```

Use `TamaOAuth`, not `Tama.OAuth`. The package serves both authorization-server
and resource-server roles and must not imply that it is nested inside a larger
runtime `Tama` application namespace.

The dependency direction is one-way:

```text
Memovee OAuth adapters ─┐
                        ├──> TamaOAuth protocol core
Tama OAuth adapters ────┘
```

`TamaOAuth` owns reusable, policy-free mechanics:

- bounded OAuth parameter parsing and validation;
- canonical scope, issuer, resource, and redirect representations;
- OAuth error values and protocol response construction;
- PKCE `S256` generation and verification;
- authorization-server and protected-resource metadata builders;
- Client ID Metadata Document parsing, validation, and safe-fetch contracts;
- public-client and `private_key_jwt` authentication mechanics;
- client assertion validation and replay-record contracts;
- JWT claim construction and verification;
- asymmetric JWK/JWKS serialization, parsing, and key selection;
- refresh-token rotation and family-replay state decisions;
- revocation and introspection request/response types; and
- injectable clock, randomness, HTTP-fetching, key-provider, and storage
  behaviours where nondeterministic or application-owned work is required.

The package does not own:

- Ecto or Ash schemas, repositories, migrations, or database transactions;
- Eventful declarations or lifecycle transitions;
- Memovee users, Actors, grants, resource policy, or authorization decisions;
- Tama MCP principals, tools, or message execution;
- Phoenix routes, controllers, LiveViews, plugs, or consent UI;
- deployment secrets, application configuration, rate limits, telemetry sinks,
  or cleanup scheduling; or
- database tables shared between Memovee and Tama.

The core must not depend on Memovee, Tama, Phoenix, Ecto, Ash, or Eventful.
Framework integrations may be added later only as optional thin layers that
depend on the core. Transactions and lock ordering stay in application
Managers because only the application can enforce its persistence and Eventful
invariants atomically.

Conceptually:

```text
MCP client -> Tama /mcp/app without token
Tama       -> 401 with path-specific protected-resource metadata
MCP client -> discovers Memovee as the authorization server
MCP client -> Memovee authorization endpoint with PKCE and resource
User       -> signs in to Memovee and approves or denies
Memovee    -> returns a one-time authorization code to the client callback
MCP client -> exchanges the code at Memovee's token endpoint
Memovee    -> issues a Tama MCP access token and refresh token
MCP client -> calls Tama /mcp/app with the access token
Tama       -> validates the token and derives the Memovee Actor from `sub`
```

## Accepted decisions

- Implement an OAuth 2.1 authorization server in Memovee; OpenID Connect is not
  required for this flow.
- Use authorization code with PKCE `S256`; do not implement the implicit grant
  or resource-owner password grant.
- Configure one exact protected resource URI for Tama `/mcp/app`.
- Define one initial scope, `mcp.message`.
- Bind every request, code, grant, access token, and refresh token to the exact
  resource and normalized scope.
- Use the authenticated Memovee user Actor as the grant subject.
- Put the Memovee user Actor UUID in the access token's standard `sub` claim.
- Do not create a Memovee agent Actor merely because an OAuth client was
  authorized.
- Keep the OAuth `client_id` distinct from Memovee's existing agent API-token
  credential ID, which is also currently named `client_id` at the API boundary.
- Store authorization codes and refresh tokens only as cryptographic digests.
- Use short-lived JWT access tokens signed asymmetrically by Memovee.
- Publish Memovee's public signing keys through a JWKS endpoint.
- Never share Memovee's private signing key with Tama.
- Make Client ID Metadata Documents the primary client registration mechanism.
- Retain pre-registration and Dynamic Client Registration only as explicit
  compatibility paths.
- Revalidate mutable authorization at token refresh and introspection time.
- Reject inactive Memovee user Actors.
- Keep browser session tokens, agent API tokens, and OAuth credentials as
  separate token contexts even when they share `actor_tokens` storage.
- Use Memovee's UUIDv7 and per-schema Manager conventions throughout.
- Use Eventful transitions for persisted OAuth request and grant lifecycles.
- Use `TamaOAuth` for shared protocol mechanics in both Memovee and Tama.
- Keep all resource-specific policy and persistence behind application-owned
  modules or explicit `TamaOAuth` behaviours.
- Develop against the sibling package by path only when necessary locally;
  committed application dependencies must use a released Hex version or an
  immutable Git tag.

## Non-goals

The first Memovee OAuth change does not:

- implement `/mcp/app` in Tama;
- implement Tama's `message` tool;
- make Memovee's API an OAuth protected resource;
- authorize the Tama MCP token at Memovee's memory API;
- implement OAuth token exchange for later Tama-to-Memovee API calls;
- add multiple Tama application resources or multiple scopes;
- introduce OpenID Connect ID tokens or a UserInfo endpoint;
- replace Memovee's browser authentication;
- replace existing agent API credentials;
- share OAuth database tables between Memovee and Tama;
- move Memovee Actor or Eventful lifecycle policy into `TamaOAuth`; or
- require either application to adopt Ash.

If Tama later fetches Memovee memory while executing `message`, that is a
separate service-to-service authorization boundary. The incoming Tama MCP token
must not be forwarded to Memovee's API.

## Existing package evaluation

`ash_authentication_oauth2_server` is useful prior art for PKCE, CIMD hardening,
discovery, consent separation, and refresh-token rotation. It is not the
implementation dependency for this feature because its public API is built
around Ash resources and Ash actors, while Memovee and Tama use application-
owned Ecto/Eventful models. Its current documented profile also does not cover
the complete cross-service contract required here: ChatGPT
`private_key_jwt`, asymmetric signing with public JWKS, authenticated
introspection, and immediate access-token-reference revocation.

Use its protocol behavior and tests as comparative reference where useful, but
do not introduce Ash solely to obtain OAuth mechanics and do not copy its
stateless access-token assumptions into this design.

## Canonical identifiers

All production identifiers are configuration, never request-derived host
values.

```text
Memovee issuer:
  https://<memovee-host>

Tama MCP app resource:
  https://<tama-host>/mcp/app

Memovee authorization-server metadata:
  https://<memovee-host>/.well-known/oauth-authorization-server

Memovee JWKS:
  https://<memovee-host>/.well-known/jwks.json
```

The configured Tama resource URI must match exactly in:

- Tama protected-resource metadata;
- Memovee authorization requests;
- Memovee token requests;
- persisted OAuth requests, codes, and grants;
- the access-token `aud` claim;
- refresh-token authorization checks; and
- Tama audience validation.

No trailing-slash alias, request-host fallback, or alternate audience is
accepted.

## OAuth profile

The initial server supports:

```text
response_types_supported: code
grant_types_supported: authorization_code, refresh_token
code_challenge_methods_supported: S256
token_endpoint_auth_methods_supported: none, private_key_jwt
scopes_supported: mcp.message
```

Public MCP clients use `token_endpoint_auth_method=none` with PKCE. Clients that
publish suitable key metadata may use `private_key_jwt`.

Access tokens are Bearer tokens and must be sent only in the HTTP
`Authorization` header. Tokens in query parameters are rejected and must never
appear in redirects, logs, telemetry, or rendered HTML.

## Authorization-server metadata

Memovee publishes:

```http
GET /.well-known/oauth-authorization-server
```

The response includes at least:

```json
{
  "issuer": "https://memovee.example",
  "authorization_endpoint": "https://memovee.example/auth/authorizations/new",
  "token_endpoint": "https://memovee.example/auth/tokens",
  "registration_endpoint": "https://memovee.example/auth/registrations",
  "revocation_endpoint": "https://memovee.example/auth/revocations",
  "introspection_endpoint": "https://memovee.example/auth/introspections",
  "jwks_uri": "https://memovee.example/.well-known/jwks.json",
  "response_types_supported": ["code"],
  "grant_types_supported": ["authorization_code", "refresh_token"],
  "code_challenge_methods_supported": ["S256"],
  "token_endpoint_auth_methods_supported": ["none", "private_key_jwt"],
  "token_endpoint_auth_signing_alg_values_supported": ["RS256"],
  "client_id_metadata_document_supported": true,
  "scopes_supported": ["mcp.message"],
  "protected_resources": ["https://tama.example/mcp/app"],
  "authorization_response_iss_parameter_supported": true
}
```

Omit `registration_endpoint` if DCR is intentionally disabled. Metadata must
describe only implemented behavior.

Memovee does not publish Tama's protected-resource metadata. Tama owns:

```text
GET /.well-known/oauth-protected-resource/mcp/app
```

and lists Memovee's issuer in its `authorization_servers` field.

## Client registration and metadata

### Client ID Metadata Documents

HTTPS URL client IDs are the primary path. Implement the reusable document
parsing, validation, and SSRF-safe fetch policy in `TamaOAuth`, informed by
Tama's existing bounded behavior. Use a `Req`-backed fetcher behind the package
fetch contract; Memovee owns the production allowlist and network policy.

The fetcher must:

- accept only configured client IDs or configured HTTPS client-ID prefixes;
- require the fetched document's `client_id` to equal its URL exactly;
- require a non-empty client name;
- validate all redirect URIs;
- allow HTTPS redirects and loopback HTTP redirects only;
- support ephemeral loopback ports without accepting arbitrary callback paths;
- require authorization-code support;
- intersect token endpoint authentication methods with Memovee's methods;
- require a same-origin JWKS URI when `private_key_jwt` is used;
- enforce response size, redirect, timeout, scheme, port, and address bounds;
- reject credentials, fragments, unsupported schemes, and private-network SSRF
  targets unless explicitly enabled for local development;
- cache validated metadata for a bounded duration; and
- persist a digest of the exact metadata used to start authorization.

Consent and approval must re-fetch or reload the client metadata and compare
its digest with the persisted request. A changed client name, redirect set, or
authentication method invalidates the pending request rather than silently
approving changed metadata.

### Pre-registration

Support configured client IDs for known MCP clients. Production allowlists must
be explicit and resource-specific. Allowing a client for another Memovee or Tama
integration must not implicitly authorize it for Tama `/mcp/app`.

### Dynamic Client Registration

DCR is a compatibility fallback, not the preferred path. If enabled, port
Tama's bounded registration, lifecycle, cleanup, rate limiting, and metadata
normalization. Initial dynamic clients are public and use:

```text
grant_types: authorization_code, refresh_token
response_types: code
token_endpoint_auth_method: none
```

Registration must validate `application_type` and native versus web redirect
constraints. It must not issue a client secret to a public client.

## Authorization request

Memovee exposes:

```http
GET /auth/authorizations/new
```

Required parameters are:

```text
response_type=code
client_id=<registered or metadata-document client>
redirect_uri=<exact allowed callback>
resource=https://<tama-host>/mcp/app
scope=mcp.message
state=<client state>
code_challenge=<PKCE challenge>
code_challenge_method=S256
```

Validation must occur before redirecting into the consent UI:

- bound every string field by byte length;
- require an exact configured resource;
- normalize and require exactly the supported scope set;
- require `response_type=code`;
- require a valid PKCE challenge and `S256`;
- resolve and validate client metadata;
- require an exact allowed redirect URI, subject only to the defined ephemeral
  loopback port rule;
- retain the client-provided `state` exactly within its size bound; and
- rate limit by remote address without logging raw parameters or credentials.

On success, generate an opaque request handle, persist only its SHA-256 digest,
and redirect the browser to:

```text
/auth/consent/<opaque-handle>
```

Invalid authorization requests return a bounded, non-reflective error. Do not
redirect to an unvalidated callback URI.

## Browser authentication and consent

The consent route belongs to Memovee's authenticated browser boundary. An
unauthenticated user first completes the existing Memovee login flow and then
returns to the pending consent request.

Only an active `Actor{type: :user}` may approve or deny. The current scope is
the sole source of the user Actor; request parameters cannot select an Actor.

The consent page must display:

- client name;
- whether the client metadata is verified;
- client website when present;
- callback authority;
- exact Tama resource URI;
- a human description of `mcp.message`;
- a warning for loopback callbacks or unverified dynamically registered
  clients; and
- explicit Deny and Approve actions.

The initial scope description is:

```text
Send messages to Tama for processing on your behalf.
```

The page must not display raw request handles, authorization codes, access
tokens, refresh tokens, signing material, or internal token references.

Approval must re-lock the pending request, revalidate the resource, scope,
client, redirect URI, metadata digest, user Actor, and Actor lifecycle before
creating or reusing a grant.

Denial transitions the request once and redirects to the validated client
callback with:

```text
error=access_denied
state=<original state>
iss=<Memovee issuer>
```

Approval redirects with:

```text
code=<one-time opaque authorization code>
state=<original state>
iss=<Memovee issuer>
```

## Persistence model

All ordinary OAuth schemas use `Memovee.Schema`. All keys and foreign keys use
Memovee's monotonic UUIDv7 convention. OAuth lifecycle state changes use
Eventful with `binary_id: Memovee.Eventful.UUIDv7`.

### OAuth request

```text
Memovee.OAuth.Request
oauth_requests
```

Fields:

| Field | Purpose |
| --- | --- |
| `id` | UUIDv7 primary key |
| `handle_digest` | SHA-256 digest of opaque browser handle |
| `client_id` | OAuth client identifier |
| `client_metadata_digest` | Digest of metadata shown for consent |
| `redirect_uri` | Validated callback URI |
| `resource` | Exact Tama `/mcp/app` URI |
| `scope` | Canonical `mcp.message` scope |
| `state` | Opaque client state |
| `code_challenge` | PKCE S256 challenge |
| `current_state` | `pending`, `approved`, `denied`, or `expired` |
| `expires_at` | Short request expiry |
| timestamps | Microsecond UTC timestamps |

The handle digest is unique. Index client ID and expiry. Persist request events
for approve, deny, and expire transitions.

### OAuth grant

```text
Memovee.OAuth.Grant
oauth_grants
```

Fields:

| Field | Purpose |
| --- | --- |
| `id` | UUIDv7 primary key |
| `actor_id` | Memovee user Actor that approved the client |
| `oauth_client_id` | OAuth client identifier |
| `resource` | Exact Tama `/mcp/app` URI |
| `scope` | Canonical granted scope |
| `current_state` | `pending`, `active`, or `revoked` |
| `last_used_at` | Latest successful token use or introspection |
| timestamps | Microsecond UTC timestamps |

The active grant identity is:

```text
actor_id + oauth_client_id + resource
```

Only one active grant may exist for that identity. Reauthorization with the
same scope may reuse the active grant while replacing its refresh credential.
A changed scope revokes the old grant before creating the replacement.

Grant transitions are performed by the approving user Actor. Automated expiry
or security revocation uses an explicitly defined system transition actor; it
must not cast lifecycle fields directly.

### Authorization code

```text
Memovee.OAuth.Code
oauth_codes
```

Fields bind the code to:

- SHA-256 code digest;
- OAuth grant;
- redirect URI;
- resource;
- scope;
- PKCE challenge;
- expiry; and
- one-time consumption timestamp.

The raw code is returned once and never persisted. Token exchange locks and
consumes the code in the same transaction that issues credentials.

### OAuth access association

```text
Memovee.OAuth.Access
oauth_accesses
```

This table associates an Actor-owned token reference with exactly one OAuth
grant. It allows revocation, introspection, cleanup, and refresh validation to
reload the complete authorization family without storing raw JWTs.

### Actor token contexts

Reuse `actor_tokens` with explicit OAuth constructors and verifiers. Use exact
contexts that cannot collide with browser or direct API credentials:

```text
oauth_access
oauth_refresh
```

An `oauth_access` row is a server-side reference identified by the JWT `jti`.
It stores an independent random reference value in the required
`actor_tokens.token` field, not the raw JWT or a reusable bearer credential. An
`oauth_refresh` row stores only the SHA-256 digest of the raw refresh token.

Both rows belong directly to the grant's user Actor. `oauth_accesses` binds
them to the grant.

Do not reuse the existing `api` context and do not interpret an OAuth
`client_id` as an `actor_tokens.id`.

### Client registration and replay

When DCR is enabled, add these application-owned registration tables with
Memovee UUIDv7 conventions:

```text
oauth_client_registrations
oauth_client_registration_events
```

Whenever `private_key_jwt` is enabled, add the replay table independently of
whether DCR is enabled:

```text
oauth_client_replays
```

Replay records contain only a digest and expiry. Client assertions are bounded,
signature-verified, audience-checked, short-lived, and one-time.

## Grant approval transaction

Approval is serialized and atomic:

1. lock the pending authorization request;
2. reload the active Memovee user Actor;
3. revalidate the configured resource and supported scope;
4. refresh and compare client metadata;
5. resolve the active grant identity;
6. lock any existing grant;
7. reuse or revoke and replace the grant according to scope;
8. generate a one-time authorization code and persist its digest;
9. transition the request to approved; and
10. commit before redirecting to the client.

Concurrent approvals must not create two active grants. Unique-constraint races
may be retried a small, bounded number of times after reloading authoritative
state.

## Token endpoint

Memovee exposes an `application/x-www-form-urlencoded` endpoint:

```http
POST /auth/tokens
```

It accepts only:

```text
grant_type=authorization_code
grant_type=refresh_token
```

JSON request bodies, unsupported grant types, Basic secrets for public clients,
duplicate credential mechanisms, and unbounded fields are rejected with OAuth
errors.

### Authorization-code exchange

The transaction must:

1. validate client authentication and rate limits;
2. resolve the exact resource policy;
3. validate bounded client ID, code, redirect URI, and PKCE verifier;
4. digest and load the unconsumed, unexpired code;
5. lock the grant before locking the code;
6. verify client, redirect URI, resource, scope, Actor, and PKCE bindings;
7. require an active user Actor and active grant;
8. consume the code;
9. revoke or replace an earlier refresh credential for the grant;
10. create an access-token reference;
11. create a refresh-token digest;
12. sign the access token; and
13. commit all credential changes together.

The successful response is:

```json
{
  "access_token": "<signed JWT>",
  "token_type": "Bearer",
  "expires_in": 600,
  "refresh_token": "<opaque token>",
  "scope": "mcp.message"
}
```

### Refresh exchange

The initial implementation uses refresh-token rotation with family replay
detection. A successful exchange invalidates the presented refresh credential,
creates a replacement, and creates a new short-lived access-token reference.

The refresh transaction must lock the grant first, then the refresh credential.
It revalidates:

- client identity;
- resource;
- exact or reduced permitted scope;
- active grant;
- active Memovee user Actor;
- token ownership and grant association;
- refresh absolute and idle lifetimes; and
- replay-family invariants.

Reusing an invalidated refresh token revokes the credential family rather than
issuing another access token.

Tama's existing stable-refresh implementation is a known MCP-client
compatibility workaround. Do not silently copy that exception. Live acceptance
with the current Codex client is required. If the current client still cannot
retain rotated refresh tokens, record and approve a separate interoperability
decision before adopting stable refresh behavior in Memovee.

## Access-token format

Issue JWT access tokens with an asymmetric algorithm and a `kid` header. Use
`RS256` initially for broad interoperability.

Required claims:

```json
{
  "iss": "https://memovee.example",
  "sub": "<Memovee user Actor UUID>",
  "aud": "https://tama.example/mcp/app",
  "client_id": "<OAuth client ID>",
  "scope": "mcp.message",
  "jti": "<oauth_access ActorToken UUID>",
  "iat": 1787900000,
  "exp": 1787900600
}
```

The access-token lifetime defaults to ten minutes and is configuration-owned.
Do not put email, user display data, raw grant secrets, or mutable profile data
in the token.

`sub` is the stable Memovee Actor UUID. Tama must treat the principal as the
pair `{iss, sub}` and must never substitute email as identity.

## Signing keys and JWKS

Memovee owns the private signing keys. Production startup fails when signing
configuration is absent or invalid.

Publish public keys at:

```http
GET /.well-known/jwks.json
```

Requirements:

- publish only public key material;
- return a stable `kid` for each active verification key;
- sign new tokens with exactly one configured active key;
- permit an overlap window with the previous public key during rotation;
- remove retired public keys only after every token they signed has expired;
- set appropriate cache headers;
- never log private keys or raw environment values; and
- reject algorithms other than the configured asymmetric allowlist.

Do not use Tama's current `HS256` access-token arrangement across services.
Sharing an HMAC secret would allow Tama to mint tokens that appear to come from
Memovee.

## Introspection

To preserve Memovee's Actor lifecycle as a prompt authorization kill switch,
implement authenticated RFC 7662-style introspection:

```http
POST /auth/introspections
Content-Type: application/x-www-form-urlencoded

token=<access token>
```

Only the configured Tama resource server may introspect tokens for
`/mcp/app`. Authenticate Tama using a confidential service credential,
preferably `private_key_jwt` with an explicitly configured Tama JWKS.

An active response includes:

```json
{
  "active": true,
  "iss": "https://memovee.example",
  "sub": "<Actor UUID>",
  "aud": "https://tama.example/mcp/app",
  "client_id": "<OAuth client ID>",
  "scope": "mcp.message",
  "grant_id": "<OAuth grant UUID>",
  "jti": "<token reference UUID>",
  "iat": 1787900000,
  "exp": 1787900600
}
```

Unknown, expired, revoked, incorrectly bound, or inactive-Actor tokens return:

```json
{"active": false}
```

Do not reveal why an unknown token is inactive. Rate limit introspection by
resource-server identity and remote address. Tama may cache a positive result
for a very short bounded interval, but the cache must never exceed token expiry.

## Revocation

Memovee exposes:

```http
POST /auth/revocations
```

The endpoint accepts access or refresh tokens, authenticates the OAuth client,
and follows the non-oracular revocation response contract: unknown tokens do
not reveal their existence.

For a valid token family, revocation must:

- lock the grant;
- verify client, Actor, resource, token, and grant bindings;
- transition the grant to revoked;
- invalidate every associated access-token reference;
- invalidate every associated refresh token and rotation-family record; and
- emit safe audit metadata without raw credentials.

The Memovee user must later receive a connected-applications UI that lists
active grants and allows revocation by grant. The endpoint implementation is
part of this feature; a polished management UI may follow after the first MCP
acceptance if necessary.

## Scope and resource policy

Create an explicit policy module, expected to be:

```text
Memovee.OAuth.TamaMCPAppPolicy
```

It owns:

```text
resource()
supported_scopes()
default_scopes()
normalize_scope(scope)
parse_scope(scope)
allowed_client_id?(client_id)
```

Initial values are:

```text
resource: configured https://<tama-host>/mcp/app
supported scopes: mcp.message
default scopes: mcp.message
```

Unknown resources and scopes fail closed. Do not construct atoms from resource
or scope input.

## Rate limiting and remote fetch safety

Apply independent limits to:

- authorization starts by remote address;
- client registrations by remote address;
- token exchanges by remote address and client ID digest;
- revocations by remote address and client ID digest;
- introspections by remote address and Tama credential;
- client metadata fetch failures; and
- unknown key IDs or client assertion replays.

Rate-limit keys contain digests rather than raw tokens or client assertions.
Responses include bounded retry guidance where appropriate.

Remote client metadata and JWKS fetching must use `Req`, bounded redirect
following, public-network address checks, response-size limits, JSON content
validation, and short timeouts. DNS resolution and redirects must be rechecked
to prevent SSRF rebinding.

## Cleanup and retention

Run bounded periodic cleanup for:

- expired pending authorization requests and request events;
- expired and consumed authorization codes;
- expired access-token references;
- expired refresh-token families;
- expired client assertion replay records;
- abandoned dynamic client registrations; and
- old revoked grants and their events after the retention window.

Cleanup must lock grants before mutating grant credential families and must
recheck expiry after acquiring the lock. It must process bounded batches and
schedule continuation rather than loading an unbounded table.

Memovee does not currently include Tama's cleanup scheduler and cache stack.
Choose an application-owned supervised worker or add an explicitly justified
job scheduler. The OAuth domain behavior must not depend directly on a
particular scheduler library.

## Module structure

Expected shared package modules:

```text
TamaOAuth
TamaOAuth.AuthorizationRequest
TamaOAuth.ClientAuthentication
TamaOAuth.ClientAuthentication.None
TamaOAuth.ClientAuthentication.PrivateKeyJWT
TamaOAuth.ClientMetadata
TamaOAuth.ClientMetadata.Fetcher
TamaOAuth.Error
TamaOAuth.Introspection
TamaOAuth.JWT
TamaOAuth.JWKS
TamaOAuth.Metadata.AuthorizationServer
TamaOAuth.Metadata.ProtectedResource
TamaOAuth.PKCE
TamaOAuth.RefreshToken
TamaOAuth.Revocation
TamaOAuth.Scope
TamaOAuth.TokenRequest
TamaOAuth.URI
```

These names identify initial ownership boundaries, not permission to create a
large speculative API. Introduce each public module with the first tested
vertical slice that consumes it. Prefer explicit data structures and small
behaviours over callbacks that mirror an application's entire OAuth context.

Expected Memovee domain modules:

```text
Memovee.OAuth
Memovee.OAuth.Access
Memovee.OAuth.Authorization
Memovee.OAuth.Client
Memovee.OAuth.Client.Registration
Memovee.OAuth.Client.Registration.Manager
Memovee.OAuth.Client.Replay
Memovee.OAuth.Code
Memovee.OAuth.Event
Memovee.OAuth.Grant
Memovee.OAuth.Grant.Credentials
Memovee.OAuth.Grant.Manager
Memovee.OAuth.Introspection
Memovee.OAuth.KeyProvider
Memovee.OAuth.RateLimiter
Memovee.OAuth.Request
Memovee.OAuth.Revocation
Memovee.OAuth.TamaMCPAppPolicy
Memovee.OAuth.Token.Exchange
```

Expected web modules:

```text
MemoveeWeb.OAuth.AuthorizationController
MemoveeWeb.OAuth.ConsentLive
MemoveeWeb.OAuth.FallbackController
MemoveeWeb.OAuth.IntrospectionController
MemoveeWeb.OAuth.JWKSController
MemoveeWeb.OAuth.MetadataController
MemoveeWeb.OAuth.RegistrationController
MemoveeWeb.OAuth.RegistrationJSON
MemoveeWeb.OAuth.RevocationController
MemoveeWeb.OAuth.TokenController
MemoveeWeb.OAuth.TokenJSON
```

Repo queries, persistence, locking, transactions, and cleanup orchestration
belong in Managers or focused service modules. Schemas remain focused on
fields, associations, changesets, transitions, and pure data behavior.

Memovee modules call `TamaOAuth` for protocol validation, cryptography, and
response construction. They must not duplicate PKCE, JWT, JWK, metadata, CIMD,
client assertion, or OAuth error logic locally. Conversely, `TamaOAuth` must
not call `Memovee.Repo`, inspect an Accounts Actor, or perform an Eventful
transition.

Controllers remain REST-focused: validate transport shape, call the OAuth
domain, and render the protocol response. They must not own grant transactions
or token cryptography.

## Router boundaries

Add a dedicated OAuth API pipeline that:

- accepts JSON where metadata or registration responses require it;
- accepts form encoding for token, revocation, and introspection endpoints;
- applies no browser session assumptions to protocol endpoints;
- emits no-store headers for credential responses; and
- uses OAuth-specific fallback rendering.

The authorization start route is a browser entry point. The consent LiveView
must be inside the authenticated user `live_session` and receive
`current_scope` through the existing Phoenix authentication boundary.

Conceptually:

```text
GET  /.well-known/oauth-authorization-server  public OAuth metadata
GET  /.well-known/jwks.json                    public keys
GET  /auth/authorizations/new                  browser authorization start
GET  /auth/consent/:handle                     authenticated LiveView
POST /auth/registrations                       public, rate-limited DCR
POST /auth/tokens                              OAuth form endpoint
POST /auth/revocations                         OAuth form endpoint
POST /auth/introspections                      Tama-authenticated form endpoint
```

## Configuration

Development defaults may use localhost, but production configuration must
require explicit secure values:

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

Configuration also owns request, code, access-token, refresh-token, replay,
registration, cleanup, cache, and rate-limit lifetimes.

Production must require HTTPS issuer and resource identifiers. Localhost HTTP
is allowed only in development and test.

## Dependencies

Memovee and Tama depend on `:tama_oauth`; `TamaOAuth` owns the reviewed
JOSE/JWT dependencies used for asymmetric signing, verification, and JWK
serialization. Do not expose Joken or JOSE structs as the public package API.
The public boundary uses package-owned structs and ordinary Elixir values so
the underlying cryptographic library can be replaced without changing both
applications.

Memovee already includes `Req` and Eventful. A `Req`-backed remote-document
fetcher may live in `TamaOAuth` because both applications need the same bounded
HTTP behavior, but its DNS, redirect, address, response-size, and timeout policy
must remain configurable and fail closed. Eventful remains a Memovee-only
dependency.

During local co-development an application may temporarily use:

```elixir
{:tama_oauth, path: "../tama-oauth"}
```

Do not merge or deploy a sibling path dependency. Publish and pin an initial
Hex release, or use an immutable Git tag while preparing that release. Every
package release requires its own changelog entry, documentation build, tests,
`mix precommit`, and `mix hex.build` validation.

Do not add `anubis_mcp` to Memovee. Memovee is the authorization server, not
the MCP transport server.

Rate limiting, caching, and scheduled cleanup need explicit implementations.
Prefer the smallest application-owned boundary that meets concurrency and
production needs; do not copy Tama infrastructure dependencies solely because
the OAuth domain uses them there.

## Logging and telemetry

Emit structured events for:

- authorization started, approved, denied, expired, and failed;
- client registration and metadata validation;
- authorization-code token issuance;
- refresh success, replay, and failure;
- access-token introspection;
- revocation;
- signing key selection failures;
- rate limiting; and
- cleanup invariant violations.

Safe metadata may include client ID, grant ID, token-reference ID, Actor ID,
resource, normalized scope, failure stage, and bounded reason enums.

Never log:

- raw authorization request handles;
- authorization codes;
- access tokens;
- refresh tokens;
- client assertions;
- PKCE verifiers;
- signing keys;
- browser session tokens; or
- client secrets.

## Tama integration contract

This Memovee feature is complete only when its output contract is documented
for Tama.

Tama `/mcp/app` must:

- consume `TamaOAuth` resource-server metadata, JWT/JWKS, scope, and
  introspection primitives rather than maintaining a second implementation;
- publish path-specific protected-resource metadata;
- list Memovee's exact issuer as its authorization server;
- challenge unauthenticated clients with the path-specific metadata URL and
  `mcp.message` scope;
- fetch and cache Memovee's JWKS safely;
- allow only the configured access-token algorithm;
- validate `iss`, exact `aud`, `exp`, `iat`, `jti`, `client_id`, `scope`, and
  UUIDv7 `sub`;
- require positive Memovee introspection for each `message` authorization,
  subject only to the documented short cache bound;
- expose `sub` as `memovee_actor_id` in the authenticated MCP principal;
- require `mcp.message` for the only tool; and
- inject the Actor ID into message execution rather than accepting it as tool
  input.

Tama owns a thin application adapter that turns a successfully verified
`TamaOAuth` principal into its request context. That adapter may call Memovee
introspection and construct Tama's `memovee_actor_id`, but it must not teach the
shared package how Tama executes tools or how Memovee stores Actors.

The tool contract remains:

```json
{
  "name": "message",
  "input": {
    "model": "some-model-graph-on-tama",
    "body": "Natural-language text to process"
  }
}
```

The authenticated execution context adds:

```text
memovee_actor_id = validated access-token sub
oauth_client_id  = validated access-token client_id
oauth_grant_id   = server-side identity when returned by introspection
```

## Memovee API boundary after MCP authorization

Knowing the Actor UUID does not itself authorize Tama to call Memovee's API.
If `message` later reads or writes posts, tags, or taggings, implement a second
credential intended for the Memovee API.

The preferred later design is a short-lived delegated credential containing:

```text
aud = exact Memovee API resource
sub = Memovee user Actor UUID
act = Tama service identity
```

Do not forward the Tama MCP access token to Memovee's API. Do not accept an
unsigned `actor_id` header protected only by network location.

## Error contract

OAuth protocol endpoints return OAuth errors, not Memovee's JSON:API error
arrays. This is a protocol-specific exception to the application's normal API
error shape.

Use only the applicable standard errors:

```text
invalid_request
invalid_client
invalid_grant
invalid_target
invalid_scope
unsupported_grant_type
temporarily_unavailable
access_denied
```

Errors are bounded and non-oracular. Internal exception details, database
constraints, token existence, Actor existence, and cryptographic failure
details are never exposed.

Memovee's existing non-OAuth APIs continue to use their existing JSON:API error
contract.

## Test plan

### TamaOAuth package tests

- no compile-time dependency on Memovee, Tama, Phoenix, Ecto, Ash, or Eventful;
- RFC-shaped success and error values without framework response structs;
- PKCE `S256` vectors and constant-time verifier comparison;
- issuer, resource, redirect, and scope canonicalization fixtures shared by
  both applications;
- CIMD validation and bounded fetch-policy fixtures;
- public-client and `private_key_jwt` authentication vectors;
- JWT signing and verification with rotating asymmetric keys;
- public-only JWKS serialization and key-selection failures;
- refresh rotation and replay-family state-machine cases;
- introspection and revocation request/response fixtures;
- deterministic clock, random-source, HTTP-fetcher, and key-provider fakes;
- generated ExDoc without warnings;
- `mix precommit`; and
- `mix hex.build` with only intended package files.

### Schema and transition tests

- UUIDv7 primary and foreign keys for every OAuth schema.
- Request transition matrix and immutable authorization bindings.
- Grant approve and revoke transitions with Accounts Actors.
- Active-grant uniqueness under concurrent approval.
- Code, request-handle, refresh-token, and replay digests.
- Actor token context isolation.

### Client tests

- valid CIMD document;
- client ID mismatch;
- metadata change between authorization and consent;
- exact and ephemeral-loopback redirect matching;
- HTTPS and localhost constraints;
- SSRF, redirect, size, timeout, and content-type rejection;
- allowlist and prefix containment;
- same-origin client JWKS enforcement;
- DCR validation and cleanup when enabled; and
- `private_key_jwt` key selection, audience, expiry, and replay rejection.

### Authorization tests

- exact authorization request contract;
- PKCE `S256` requirement;
- exact resource and scope;
- authenticated active user requirement;
- inactive Actor rejection;
- consent content and stable DOM IDs;
- approval callback with code, state, and issuer;
- denial callback with `access_denied`, state, and issuer;
- no redirect to an invalid callback;
- expired or replayed consent handle rejection; and
- concurrent approval creates one active grant.

### Token tests

- one-time authorization-code exchange;
- PKCE verifier mismatch;
- client, redirect, resource, scope, code, grant, and Actor binding failures;
- form-content-type enforcement;
- JWT header and required claims;
- exact audience and ten-minute lifetime;
- access reference and refresh digest persistence;
- refresh rotation and replay-family revocation;
- inactive Actor refresh rejection;
- revoked grant refresh rejection;
- transactional rollback on partial issuance failure; and
- no raw credential leakage in logs or telemetry.

### JWKS and introspection tests

- public JWKS contains no private parameters;
- active and overlapping rotation keys;
- unknown or disallowed `kid` rejection;
- authenticated Tama introspection;
- active token response;
- inactive response for expired, revoked, unknown, wrongly bound, or inactive
  Actor tokens;
- introspection rate limiting; and
- no token-existence oracle.

### Controller and LiveView tests

- authorization-server metadata matches implemented endpoints;
- token, revocation, registration, and introspection content-type behavior;
- OAuth cache and no-store headers;
- consent route preserves login return path;
- tests select key consent elements by their DOM IDs; and
- protocol endpoints never render JSON:API errors accidentally.

### Race tests

- concurrent approval;
- code double exchange;
- simultaneous refreshes;
- refresh versus revocation;
- refresh versus reauthorization;
- introspection versus revocation;
- Actor deactivation versus token issuance; and
- client registration cleanup versus authorization.

### End-to-end acceptance

With a real MCP client:

1. connect to Tama `/mcp/app` without a token;
2. discover Memovee through Tama protected-resource metadata;
3. discover Memovee authorization-server metadata;
4. resolve or register the client;
5. complete Memovee login and consent;
6. exchange the code with PKCE;
7. call Tama `message` successfully;
8. confirm Tama receives the expected Memovee Actor UUID;
9. allow the access token to expire and refresh successfully;
10. revoke the grant and confirm subsequent access fails; and
11. deactivate the Actor and confirm introspection fails closed.

Live acceptance must observe at least two access-token expiries so refresh
rotation behavior is verified against the actual client.

## Implementation phases

### Phase 0: TamaOAuth contract foundation

- Establish `TamaOAuth` package CI, documentation, semantic-versioning, and
  release checks.
- Add package-owned OAuth error, URI/resource, scope, clock, randomness, and
  PKCE primitives.
- Add shared conformance fixtures that Memovee and Tama can consume without
  depending on either application repository.
- Select reviewed JOSE/JWT dependencies behind package-owned APIs.
- Define only the adapter behaviours required by the first authorization-code
  vertical slice.
- Publish an initial pre-1.0 Hex release before merging production application
  dependencies.

### Phase 1: OAuth foundation

- Add the released `:tama_oauth` dependency to Memovee.
- Generate OAuth foundation migrations with `mix ecto.gen.migration`.
- Add Request, Grant, Code, Access, and lifecycle event schemas.
- Add Memovee resource policy, key-provider, configuration, and domain facade.
- Add focused schema and transition tests.

### Phase 2: Client trust

- Add bounded `TamaOAuth` remote JSON fetching with Req.
- Add shared Client ID Metadata Document validation and Memovee-owned caching
  and persistence.
- Add pre-registration policy.
- Add shared DCR and client assertion mechanics only where current MCP client
  acceptance requires them; keep registrations and replay rows in Memovee.
- Add SSRF, redirect, replay, and rate-limit tests.

### Phase 3: Authorization and consent

- Add authorization start controller.
- Add authenticated consent LiveView.
- Implement approve, deny, expiry, grant reuse, and code issuance transactions.
- Add controller, LiveView, and concurrency tests.

### Phase 4: Tokens and keys

- Add shared asymmetric signing/JWKS mechanics, the Memovee key provider, and
  the Memovee JWKS endpoint.
- Add authorization-code exchange.
- Add rotating refresh tokens and replay-family behavior.
- Add revocation, cleanup, and safe telemetry.
- Add token and race tests.

### Phase 5: Tama verification support

- Add the same released `:tama_oauth` version to Tama.
- Implement the thin Tama resource-server adapter and authenticated principal
  construction.
- Add authenticated introspection to Memovee and its client adapter to Tama.
- Publish final authorization-server metadata.
- Provide Tama with issuer, resource, scope, JWKS, and introspection contract.
- Add cross-repository integration fixtures without sharing secrets.

### Phase 6: Live MCP acceptance

- Implement or enable Tama `/mcp/app` and `message` in its own change.
- Connect a real current MCP client.
- Verify identity, refresh, revocation, and Actor deactivation behavior.
- Record any client-specific compatibility decision before weakening a protocol
  invariant.

## Porting guide from Tama

Reuse conceptually:

- persisted request, grant, code, and token association boundaries;
- PKCE and exact binding validation;
- transaction lock ordering;
- client metadata and DCR hardening;
- consent revalidation;
- revocation and cleanup behavior;
- rate-limit dimensions;
- safe event metadata; and
- race-test coverage.

Replace explicitly:

| Tama behavior | Memovee behavior |
| --- | --- |
| Tama is issuer and resource server | Memovee is issuer; Tama is remote resource server |
| Root user may consent | Any authenticated active Memovee user may consent |
| Grant belongs to generated managed Bot | Grant belongs directly to Memovee user Actor |
| Bot Actor is JWT `sub` | User Actor UUID is JWT `sub` |
| Protected role reconciliation | Exact `mcp.message` policy without Tama Roles |
| Local HS256 signing and verification | Memovee asymmetric signing and Tama JWKS verification |
| Local database grant validation | Authenticated cross-service introspection |
| Stable refresh compatibility workaround | Rotating refresh tokens unless separately approved |
| Tama UUID/schema conventions | `Memovee.Schema` monotonic UUIDv7 conventions |
| Tama infrastructure cache/jobs | Memovee-owned cache, limiter, and cleanup boundaries |

Move shared mechanics into `TamaOAuth` before copying them into Memovee. Extract
one tested vertical slice at a time: first value types and PKCE, then metadata
and client authentication, then JWT/JWKS and resource-server verification, and
finally refresh/introspection contracts. Keep Tama's existing implementation in
place until the corresponding package slice passes compatibility fixtures and
both applications can consume the same API.

Do not move application persistence into the package merely because both
applications use Ecto. Memovee and Tama have different schemas, lifecycle
rules, and authorization ownership. Reuse protocol decisions and conformance
fixtures; adapt durable state through application-owned Managers.

## Acceptance criteria

The coordinated feature is complete when:

- Memovee and Tama consume the same released `tama_oauth` protocol version;
- the shared package contains no Memovee, Tama, Phoenix, Ecto, Ash, or Eventful
  dependency;
- shared PKCE, metadata, client authentication, JWT/JWKS, scope, OAuth error,
  and introspection behavior is not duplicated in either application;
- OAuth authorization-server metadata is accurate and public;
- Memovee exposes a public JWKS containing only public keys;
- only the exact Tama `/mcp/app` resource is accepted;
- only `mcp.message` is accepted and issued;
- authorization code with PKCE `S256` works for supported MCP clients;
- the consent UI authenticates the user and displays the exact client,
  callback, resource, and permission;
- denial and approval preserve state and issuer correctly;
- grants belong directly to active Memovee user Actors;
- JWT `sub` equals the approving Memovee Actor UUID;
- JWT `aud` equals the exact configured Tama resource;
- raw codes and refresh tokens are never persisted;
- access tokens are signed asymmetrically and expire promptly;
- refresh, revocation, introspection, and cleanup fail closed;
- Actor deactivation makes introspection inactive;
- client metadata fetching is bounded against SSRF and metadata changes;
- concurrent approval, exchange, refresh, and revocation preserve invariants;
- no raw credential appears in logs, telemetry, error bodies, or UI;
- focused tests and the full Memovee suite pass;
- `mix precommit` passes; and
- a real MCP client can authorize through Memovee and call Tama `message` with
  the correct Memovee Actor identity.

## Delivery boundary

Deliver this as three coordinated repositories:

1. `tama-oauth` implements and releases the shared protocol core;
2. Memovee implements authorization-server persistence, Eventful lifecycle,
   policy, consent, endpoints, keys, and introspection using that release; and
3. Tama implements protected-resource metadata, token validation,
   introspection, principal construction, and the `message` tool using the same
   release.

Land package changes before or with the application changes that consume them.
Coordinate all three through the canonical issuer, resource, scope, claim,
JWKS, and introspection contract defined here. No repository may depend on an
unreleased mutable sibling checkout in production or CI.
