# Authentication and Agent Tokens

Status: Implemented on 2026-08-26. Phoenix authentication, Actor
classification, human User attachment, agent ownership, centralized Actor
tokens, direct API authentication, and the agent credential UI are covered by
the repository test suite. This implementation has not been deployed.

## Goal

Add Phoenix authentication without making `User` the application principal.
`Memovee.Accounts.Actor` remains the stable identity used for authorization and
Eventful attribution. Human users and non-human agents resolve to an Actor, and
all credentials are stored in one Actor-owned token table.

The first implementation must:

- generate the standard Phoenix 1.8 LiveView authentication system;
- attach every human User to exactly one Actor;
- distinguish human and non-human principals with `Actor.type`;
- represent service accounts and bots as agent Actors without fake User rows;
- centralize browser, email, and API credentials in `actor_tokens`;
- allow a human Actor to own and manage agent Actors;
- invalidate all credentials when their Actor is inactive;
- preserve monotonic UUIDv7 primary and foreign keys;
- keep credentials and Actor lifecycle fields protected from mass assignment;
  and
- retain the generated authentication security behavior unless a documented
  Actor boundary requires a change.

This document supersedes the future Accounts Actor description in
`wip/memory-control-layer.md` where that document says Actor contains only an
ID and lifecycle state. Actor remains credential-neutral, but now also carries
the minimum principal classification and agent identifier described here.

## Accepted decisions

- `Memovee.Accounts.Actor` is the canonical application principal.
- Add `Actor.type` with exactly `:user` and `:agent` in the first version.
- Use `:agent` rather than `:bot`; agent includes bots, service accounts, and
  other non-human automation.
- `Actor.type` classifies identity. It is not an authorization role.
- A human User belongs to one Actor with `type: :user`.
- An agent is an Actor with `type: :agent`; it does not have a User row.
- Store an agent's stable, human-facing identifier on Actor.
- A User email remains a credential identifier and must not become the Actor's
  stable identifier.
- Centralize human and agent credentials in `Memovee.Accounts.Token` backed by
  `actor_tokens`.
- Every Token belongs directly to Actor.
- Keep purpose-specific token constructors and verifiers even though storage is
  shared.
- Use ownership relationships between Actors so authenticated users can manage
  only their own agents.
- Actor state is the global credential kill switch. An inactive Actor cannot
  authenticate through a session, magic link, or API key.
- API secrets are generated randomly, stored only as digests, and displayed
  only once.
- Multiple API tokens per agent are supported for rotation.
- Production API secrets are not provisioned through `priv/repo/seeds.exs`.
- Repo queries, persistence, transactions, and orchestration live in adjacent
  `Schema.Manager` modules and are exposed selectively through
  `Memovee.Accounts` delegates.

## Reference assessment

### Tama

Tama has the preferred principal boundary:

- `Tama.Accounts.Actor` classifies Actors as `:user` or `:bot`;
- `Tama.Accounts.User` belongs to Actor;
- `Tama.Accounts.Token` belongs to Actor and stores human and bot tokens;
- bots are Actors without User rows;
- an owner relationship connects the creating Actor to the bot Actor; and
- permissions attach to Actor rather than User.

The new Memovee model keeps those boundaries but calls the classification
field `type` instead of `role`. Authorization roles and permissions can be
introduced later without overloading identity type.

### Memovee Legacy

Memovee Legacy treats User as the principal. Human, external, guest, bot, and
cron identities are all rows in `users`, and `users_tokens` belongs to User.
Bots are special User rows connected to their human owner through a User
relationship. Organization service accounts add another wrapper around an
external User.

That design works but requires machine identities to masquerade as Users. The
new application must not carry that coupling forward.

## Terminology

### Actor

An Actor is a stable principal that can perform actions, own resources, and be
recorded on Eventful events. Actor survives changes to email, password,
sessions, API keys, profile data, and authorization policy.

### User

A User is the human authentication record generated from `phx.gen.auth`. It
stores email, password hash, confirmation state, and other human-login data. A
User is never used as the Eventful actor directly; its associated Actor is.

### Agent

An agent is an Actor with `type: :agent`. It represents a bot, service account,
integration, or other non-human caller. An agent has no email, password, or
browser session.

### Token

A Token is a credential record owned by Actor. Its `context` determines its
purpose and therefore its creation, verification, expiration, and revocation
rules.

## Data model overview

```text
Actor
|-- has one User when type == :user
|-- has many Tokens
|-- has many owned Actor Relationships
|-- has at most one owner relationship when type == :agent
`-- has many actor-attributed Eventful events

User
`-- belongs to Actor

Token
`-- belongs to Actor

Actor Relationship
|-- belongs to owner Actor
`-- belongs to target Actor
```

## Actor schema

Schema:

```text
Memovee.Accounts.Actor
```

Table:

```text
actors
```

Fields relevant to authentication:

| Field | Ecto type | Database type | Required | Notes |
| --- | --- | --- | --- | --- |
| `id` | `Ecto.UUID` | `uuid` | yes | Monotonic UUIDv7 |
| `type` | `Ecto.Enum` | `varchar` | yes | `:user` or `:agent` |
| `identifier` | `:string` | `citext` or normalized varchar | agent only | Stable agent name |
| `current_state` | `:string` | `varchar` | yes | `active` or `inactive` |
| `current_state_version` | `:integer` | integer | yes | Eventful lock version |
| timestamps | `:utc_datetime_usec` | timestamp | yes | Microsecond UTC |

Associations:

```elixir
has_one :user, Memovee.Accounts.User
has_many :tokens, Memovee.Accounts.Token
has_many :relationships, Memovee.Accounts.Relationship
has_many :targeted_relationships, Memovee.Accounts.Relationship,
  foreign_key: :target_actor_id
```

Constraints and invariants:

- the database permits only `user` and `agent` types;
- agent Actors require a non-empty identifier;
- non-null identifiers are unique case-insensitively;
- type and lifecycle state are never cast from public parameters;
- user and agent creation use separate Manager entry points;
- changing an existing Actor's type is not supported; and
- Actor deletion remains restricted when audit events or credentials exist.

User Actors do not need an Actor identifier in the first version. User email is
mutable authentication data and must not be duplicated as the Actor's stable
identity.

Before applying the Actor type migration to a non-empty database, inspect all
persisted Actors and classify them explicitly. A production migration must not
silently assume that every existing Actor is a human user.

## User schema

Generate the Phoenix authentication baseline with:

```sh
mix phx.gen.auth Accounts User users --live --binary-id
```

The generated User schema is then adapted to the repository conventions:

```elixir
defmodule Memovee.Accounts.User do
  use Memovee.Schema

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime_usec
    field :authenticated_at, :utc_datetime_usec, virtual: true

    belongs_to :actor, Memovee.Accounts.Actor

    timestamps(type: :utc_datetime_usec)
  end
end
```

Database rules:

```text
users.actor_id NOT NULL
UNIQUE(users.actor_id)
FOREIGN KEY users.actor_id -> actors.id ON DELETE RESTRICT
UNIQUE(users.email)
```

Registration must set `actor_id` programmatically. User parameters must never
be allowed to select an existing Actor or submit an Actor type.

## Central Actor token schema

Schema:

```text
Memovee.Accounts.Token
```

Table:

```text
actor_tokens
```

Proposed fields:

| Field | Ecto type | Database type | Required | Notes |
| --- | --- | --- | --- | --- |
| `id` | `Ecto.UUID` | `uuid` | yes | UUIDv7; public API client ID |
| `actor_id` | `Ecto.UUID` | `uuid` | yes | Credential principal |
| `token` | `:binary` | bytea | yes | Raw session token or secret digest by context |
| `context` | `:string` | varchar | yes | Credential purpose |
| `sent_to` | `:string` | varchar | no | Email destination for email tokens |
| `label` | `:string` | varchar | no | Human-facing API key label |
| `authenticated_at` | `:utc_datetime_usec` | timestamp | no | Last successful use |
| `expires_at` | `:utc_datetime_usec` | timestamp | no | Explicit API expiry when applicable |
| `revoked_at` | `:utc_datetime_usec` | timestamp | no | Durable API revocation |
| `inserted_at` | `:utc_datetime_usec` | timestamp | yes | Creation time |

Associations:

```elixir
belongs_to :actor, Memovee.Accounts.Actor
has_one :user, through: [:actor, :user]
```

Indexes:

```text
INDEX(actor_id)
UNIQUE(context, token)
INDEX(actor_id, context)
```

The `token` field is always redacted in inspected structs. Its representation
depends on context:

- session tokens follow the generated Phoenix behavior and store a random
  binary token used by the signed browser session;
- email and API secrets store a SHA-256 digest of the presented secret; and
- the plaintext email or API secret is never recoverable from the database.

Centralized storage does not imply a generic authentication function. Each
credential class retains a narrow constructor and verifier.

## Token contexts

| Context | Principal | Secret storage | Validity | Revocation behavior |
| --- | --- | --- | --- | --- |
| `session` | user Actor | generated session token | generated session window | delete on logout or security reset |
| `login` | user Actor | SHA-256 digest | short magic-link window | consume on use |
| `change:<email>` | user Actor | SHA-256 digest | generated email-change window | consume on use |
| `api` | agent Actor | SHA-256 digest | explicit expiry | set `revoked_at` or delete during cleanup |

Additional API audiences must use an explicit allowlist. Arbitrary token
contexts must not be accepted from request parameters.

## Token construction contracts

Keep the generated security logic but make Actor ownership explicit:

```elixir
Token.build_session_token(%User{})
Token.build_email_token(%User{}, context)
Token.build_api_token(%Actor{type: :agent}, attrs)
```

Human token builders use `user.actor_id`:

```elixir
%Token{
  actor_id: user.actor_id,
  token: token,
  context: "session",
  authenticated_at: authenticated_at
}
```

API token creation:

1. accepts only an active Actor with `type: :agent`;
2. generates 32 random bytes with `:crypto.strong_rand_bytes/1`;
3. Base64URL-encodes the secret without padding;
4. stores only its SHA-256 digest;
5. stores an explicit label and expiry;
6. returns the token UUID as `client_id`; and
7. returns the encoded plaintext once as `client_secret`.

The creation result is:

```elixir
{:ok,
 %{
   client_id: token.id,
   client_secret: encoded_secret,
   expires_at: token.expires_at
 }}
```

The secret must not be included in URLs, query parameters, logs, telemetry,
flash messages, or persisted LiveView state that is expected to survive a
reconnect.

## Token verification contracts

Keep separate entry points:

```elixir
Token.verify_session_token_query(token)
Token.verify_magic_link_token_query(token)
Token.verify_change_email_token_query(token, context)
Token.Manager.verify_api_token(client_id, client_secret, context)
```

Session and email verification must join Token through Actor to User and
require:

- Actor type is `:user`;
- Actor state is `active`;
- token context matches exactly;
- the generated validity window has not elapsed; and
- email token `sent_to` still matches the User email where applicable.

API verification must require:

- the client ID resolves to a Token;
- context matches the allowed API context;
- the presented secret digest securely matches the stored digest;
- the Token has not expired;
- `revoked_at` is nil;
- the owning Actor has type `:agent`; and
- the owning Actor is active.

On success, API verification updates `authenticated_at` and returns the agent
Actor. Missing, malformed, expired, revoked, wrong-context, wrong-type, and
inactive credentials all return the same unauthorized result.

## Registration transaction

`Memovee.Accounts.User.Manager.register/1` owns registration persistence. It
must create the user Actor and User atomically:

```text
begin
  insert Actor(type: :user, state: active)
  insert User(actor_id: Actor.id, generated auth fields)
commit
```

An invalid or conflicting User changeset must not leave an orphan Actor. Actor
type and Actor ID are set by trusted application code, not cast from the
registration form.

Email delivery occurs after the database transaction. A provider failure does
not make PostgreSQL and the mail provider atomic; it must be surfaced as a
recoverable pending-delivery state if registration requires confirmation.

## Agent provisioning transaction

`Memovee.Accounts.Agent.create/2` accepts the authenticated owner Actor and
trusted agent attributes. Its manager creates the agent and ownership relation
atomically:

```text
begin
  insert Actor(type: :agent, identifier: identifier, state: active)
  insert Relationship(owner_actor_id, agent_actor_id, type: owner)
commit
```

API token generation is a separate explicit action after the agent exists.
This prevents a secret from being generated and lost during navigation or an
unrelated transaction failure.

## Actor ownership relationships

Schema:

```text
Memovee.Accounts.Relationship
```

Table:

```text
actor_relationships
```

Initial fields:

| Field | Required | Notes |
| --- | --- | --- |
| `id` | yes | Monotonic UUIDv7 |
| `actor_id` | yes | Owner Actor |
| `target_actor_id` | yes | Owned agent Actor |
| `type` | yes | Only `:owner` initially |
| timestamps | yes | Microsecond UTC |

Initial constraints:

- owner and target cannot be the same Actor;
- the target must be an agent Actor, enforced by the Manager and tests;
- one owner relationship per target Actor in the first version; and
- management queries always join ownership from `current_scope.actor` rather
  than loading an arbitrary agent by ID.

Multiple owners, organizations, teams, and role-based access are outside this
phase.

## Current scope

Extend the generated `Memovee.Accounts.Scope` so the caller's Actor is always
available:

```elixir
defstruct actor: nil, user: nil
```

Browser scope creation preloads User's Actor:

```elixir
Scope.for_user(%User{} = user)
```

API authentication creates an Actor-only scope:

```elixir
Scope.for_actor(%Actor{type: :agent} = actor)
```

Application services and Eventful transitions consume
`current_scope.actor`. They must not accept a client-supplied Actor ID as the
performing identity.

Generated browser routes use the appropriate Phoenix 1.8 `live_session`
boundaries. Every LiveView layout starts with `<Layouts.app>` and receives
`current_scope` where required.

## Proposed direct API authentication

The initial direct API contract is:

```http
Authorization: Bearer <client_id>.<client_secret>
```

The API authentication plug:

1. parses the Bearer credential with strict bounds;
2. verifies the Actor API token in the fixed `api` context;
3. assigns `Scope.for_actor(actor)` as `current_scope`; and
4. returns a uniform JSON `401` response on every authentication failure.

The wire format is independent of the storage model. If a future OAuth token
exchange is required, Actor and Actor Token remain the principal and credential
foundation rather than being replaced.

## Module ownership

Proposed Accounts structure:

```text
Memovee.Accounts
|-- Actor
|   |-- Manager
|   |-- Event
|   |-- Transitions
|   `-- Transit protocol implementation
|-- Agent
|   `-- Manager
|-- User
|   |-- Manager
|   `-- Notifier
|-- Token
|   `-- Manager
|-- Relationship
|   `-- Manager
`-- Scope

MemoveeWeb
|-- UserAuth
|-- ApiAuth
`-- UserLive
    |-- Registration
    |-- Login
    |-- Confirmation
    `-- Settings
```

Likely files:

```text
lib/memovee/accounts.ex
lib/memovee/accounts/actor.ex
lib/memovee/accounts/actor/manager.ex
lib/memovee/accounts/agent.ex
lib/memovee/accounts/agent/manager.ex
lib/memovee/accounts/user.ex
lib/memovee/accounts/user/manager.ex
lib/memovee/accounts/user/notifier.ex
lib/memovee/accounts/token.ex
lib/memovee/accounts/token/manager.ex
lib/memovee/accounts/relationship.ex
lib/memovee/accounts/relationship/manager.ex
lib/memovee/accounts/scope.ex
lib/memovee_web/user_auth.ex
lib/memovee_web/api_auth.ex
lib/memovee_web/live/user_live/registration.ex
lib/memovee_web/live/user_live/login.ex
lib/memovee_web/live/user_live/confirmation.ex
lib/memovee_web/live/user_live/settings.ex
```

The generator initially places authentication persistence functions in the
aggregate Accounts context. Move Repo-backed behavior into `User.Manager` and
`Token.Manager`, leaving `Memovee.Accounts` as the public delegate façade for
human and token authentication. Agent ownership uses `Memovee.Accounts.Agent`
as its focused aggregate API backed by `Agent.Manager`.

Token owns pure token construction and query-building functions. Token Manager
owns insertion, deletion, revocation, last-use updates, and transactions.

## Migration plan

Generate migrations with Mix tasks rather than inventing timestamps.

### Phase 1: Actor classification

```sh
mix ecto.gen.migration add_type_and_identifier_to_actors
```

The migration adds Actor type and identifier, performs any verified backfill,
and then adds database constraints and indexes.

### Phase 2: Phoenix authentication

```sh
mix phx.gen.auth Accounts User users --live --binary-id
```

Adapt the generated authentication migration before applying it:

- add `users.actor_id` with UUID foreign key and restricted deletion;
- add the unique User-per-Actor index;
- rename generated `users_tokens` to `actor_tokens` in the migration;
- replace `user_id` with `actor_id`;
- retain email, context, token, `sent_to`, and authentication timestamps;
- add API label, explicit expiry, and revocation fields; and
- use UUIDv7-compatible `:binary_id` columns and microsecond UTC timestamps.

Adapt the generated `UserToken` module and references to
`Memovee.Accounts.Token`.

### Phase 3: Agent ownership

```sh
mix ecto.gen.migration create_actor_relationships
```

Add owner and target UUID foreign keys, ownership constraints, and lookup
indexes.

Do not rewrite an already-applied migration to reorder these changes. If any
development migration has already been applied, add a new migration and prove
both upgrade-from-current and migrate-from-empty behavior.

## Provisioning experience

The authenticated agent credential flow is:

1. list agent Actors owned by `current_scope.actor`;
2. create an agent with a unique identifier;
3. open the agent credential page;
4. generate a labeled API token;
5. show client ID, client secret, and expiry exactly once;
6. list token metadata without secret material;
7. rotate by creating a second token before revoking the first; and
8. revoke individual tokens or deactivate the entire agent Actor.

Required UI states include empty lists, creation validation, one-time-secret
warning, copy affordances, expiry, last-use time, revoked state, and failures
that do not expose credential details.

Production keys are created interactively or through an explicit release/Mix
task whose output is captured by a secret manager. Seeds may create development
fixtures but must not contain, persist, or log a production plaintext secret.

## Security invariants

- Actor type cannot be supplied by public User or agent forms.
- User registration cannot attach to an arbitrary Actor ID.
- Agent creation always records its authenticated owner.
- Agent management always scopes by the owner relationship.
- Token context is selected by trusted code, not arbitrary request input.
- API tokens can be created only for active agent Actors.
- Human Actors cannot authenticate with API tokens.
- Agent Actors cannot authenticate with browser or email tokens.
- Every token verifier checks Actor state.
- API secrets contain at least 256 bits of randomness.
- API and email secrets are stored only as SHA-256 digests.
- Plaintext API secrets are shown once and never written to application logs.
- Token IDs are not secrets and are insufficient without the client secret.
- Revocation and Actor deactivation take effect on the next request.
- Authentication errors do not reveal whether a client ID, Actor, or token
  exists.
- Eventful attribution uses the Actor resolved from trusted authentication
  state.

## Implementation phases

### Phase 0: Stabilize the Actor baseline

- finish the current Actor Eventful lifecycle work;
- confirm Actor events use monotonic UUIDv7;
- run the focused Actor tests; and
- preserve the existing working-tree changes before generator edits touch the
  Accounts context.

### Phase 1: Actor classification

- add Actor type and identifier migration;
- add database constraints and indexes;
- add user- and agent-specific changesets and Manager functions;
- prevent type mass assignment; and
- update Actor fixtures and lifecycle tests.

### Phase 2: Generated human authentication

- run `phx.gen.auth` with LiveView and binary IDs;
- adapt User and Token to `Memovee.Schema` and UUIDv7;
- attach User and Token to Actor;
- move persistence into Managers;
- extend current scope with Actor;
- preserve generated routes, controllers, LiveViews, notifier, and tests; and
- add Actor-state checks to all human authentication paths.

### Phase 3: Agent ownership and API tokens

- add Actor relationships;
- add transactional agent creation;
- add API token construction, verification, rotation, and revocation;
- add the API authentication plug and Actor scope; and
- add owner-scoped agent and token management queries.

### Phase 4: Credential UI and operational provisioning

- add authenticated agent list, new, and show LiveViews;
- implement one-time secret display without URL leakage;
- add token metadata, rotation, and revocation actions;
- add optional explicit release/Mix provisioning for headless environments;
  and
- document secure capture into the deployment secret manager.

## Test plan

### Actor classification

- accepts only user and agent types;
- rejects missing agent identifiers;
- enforces identifier uniqueness;
- prevents public type and state changes; and
- preserves Eventful activate/deactivate behavior.

### Registration and human authentication

- creates User and user Actor atomically;
- does not leave an Actor after invalid or conflicting registration;
- enforces one User per Actor;
- creates session and email tokens with `actor_id`;
- verifies generated password and magic-link behavior;
- expires and consumes tokens according to generated policy;
- revokes human tokens during password and email security changes; and
- rejects every human credential when Actor is inactive.

### Agent ownership

- creates agent Actor and ownership relationship atomically;
- rejects duplicate identifiers and self-ownership;
- creates no User row for an agent;
- lists and loads only agents owned by the current Actor; and
- rejects management by unrelated users.

### API tokens

- creates distinct client IDs and secrets;
- stores only the secret digest;
- never returns a stored secret from later reads;
- supports multiple tokens per agent;
- updates last authentication time after successful use;
- rejects malformed secrets and client IDs;
- rejects wrong-context, expired, and revoked tokens;
- rejects API tokens attached to user Actors;
- rejects tokens for inactive agent Actors;
- supports rotation without downtime; and
- returns uniform unauthorized errors.

### Web and API boundaries

- assigns User and Actor in browser current scope;
- assigns agent Actor in API current scope;
- places routes in the correct authenticated LiveView sessions;
- passes `current_scope` to `<Layouts.app>`;
- tests LiveViews through stable DOM IDs;
- does not place plaintext secrets in URLs or rendered token lists; and
- attributes protected operations to `current_scope.actor` rather than request
  parameters.

## Acceptance criteria

The design is implemented when:

- every persisted User has exactly one user Actor;
- agents authenticate without User rows;
- all human and agent credentials are stored in `actor_tokens` by Actor ID;
- browser and API authentication both resolve an active Actor;
- deactivating an Actor blocks all of its credentials immediately;
- users can create, rotate, and revoke credentials only for owned agents;
- API secrets are hashed at rest and shown only once;
- generated Phoenix authentication behavior remains covered by its adapted test
  suite;
- migrations work both from an existing pre-authentication database and from an
  empty database;
- focused Accounts, authentication, LiveView, and API tests pass;
- `mix precommit` passes; and
- `git diff --check` is clean.

## Deferred decisions

- whether public self-registration remains enabled or becomes invite-only;
- production mail provider selection and confirmation-delivery operations;
- authorization roles, permissions, and agent capabilities;
- multiple owners, organizations, and team-managed agents;
- OAuth client credentials or short-lived bearer-token exchange;
- API key expiry defaults and organization-wide rotation policy;
- external identity providers and provider subject mappings; and
- account erasure and audit-record retention policy.

These decisions must not weaken the Actor, User, and centralized Token
boundaries established by this design.

## Validation limits

The undeployed migration chain was validated from an empty test database, and
the focused Accounts, browser authentication, direct API authentication,
LiveView, and full `mix precommit` gates passed locally. The local mail adapter
was exercised by the generated tests; no production mail provider, deployed
database upgrade, production API credential, or live external request was
validated. Repository validation must not be reported as deployed acceptance.
