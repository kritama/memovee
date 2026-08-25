# Memovee Memory Control Layer

Status: Foundational schemas, Eventful lifecycle, Post invalidation, and work
selection implemented; migrations not applied and database integration tests
pending.

## Goal

Build the first canonical memory model for Memovee, which will act as the
control layer for the Tama engine.

The initial model must allow Memovee to:

- persist the canonical dense text supplied by users and agents;
- classify that text with a small, namespaced tag vocabulary;
- project a post into one or more Tama spaces and classes;
- track synchronization through an actor-attributed Eventful state machine;
- preserve UUIDv7 as the primary and foreign key standard; and
- avoid duplicating concepts, chunks, vectors, or other data owned by Tama.

The first implementation is a global, single-tenant model. Posts are editable
canonical records. Tags are global. A separate Projection records whether a
Post has been synchronized to a particular Tama target.

## Accepted decisions

- Use `Memovee.Memory` as the context.
- Follow Tama's adjacent `Schema.Manager` convention for all persistence,
  querying, transactions, and resource orchestration.
- Use context-prefixed table names for the memory domain.
- Keep posts and tags global in the first version.
- Treat Post as the canonical editable record.
- Keep `title` optional and `body` required.
- Use Tag and Tagging for topics, projects, agents, memory kinds, and similar
  classifications.
- Keep Tagging as a simple join without confidence, provenance, or metadata.
- Store Tama synchronization separately from Post in Projection.
- Use Eventful 3.3 for the Projection lifecycle.
- Use `Memovee.Accounts.Actor` as the stable account principal and Eventful
  actor.
- Keep username, email, password, provider identity, profile, roles, and
  permissions in future related Accounts schemas rather than Actor.
- Require an Accounts Actor for every Projection transition.
- Preserve strictly monotonic UUIDv7 IDs for Eventful event rows.
- Do not persist embeddings in Memovee.
- Do not expose hard deletion until the remote Tama deletion contract is
  defined.

## Context and modules

The proposed application structure is:

```text
Memovee.Accounts
`-- Actor
    `-- Manager

Memovee.Memory
|-- Post
|   `-- Manager
|-- Tag
|   `-- Manager
|-- Tagging
|   `-- Manager
`-- Projection
    |-- Manager
    |-- Event
    |-- Transitions
    `-- Transit protocol implementation

Memovee.Eventful.UUIDv7
```

Likely files:

```text
lib/memovee/accounts.ex
lib/memovee/accounts/actor.ex
lib/memovee/accounts/actor/manager.ex
lib/memovee/memory.ex
lib/memovee/memory/post.ex
lib/memovee/memory/post/manager.ex
lib/memovee/memory/tag.ex
lib/memovee/memory/tag/manager.ex
lib/memovee/memory/tagging.ex
lib/memovee/memory/tagging/manager.ex
lib/memovee/memory/projection.ex
lib/memovee/memory/projection/manager.ex
lib/memovee/memory/projection/event.ex
lib/memovee/memory/projection/transitions.ex
lib/memovee/memory/projection/transit.ex
lib/memovee/eventful/uuid_v7.ex
```

`Memory` is a bounded-domain name rather than a plural resource name. Calls
such as `Memovee.Memory.create_post/1` and
`Memovee.Memory.invalidate_projection/2` read naturally and leave room for
future memory resources that are not posts.

The aggregate contexts are thin `defdelegate` façades. Each schema remains
focused on fields, associations, changesets, and pure data behavior; its
adjacent `Manager` owns Repo access and operational behavior.

## Ownership boundary with Tama

### Memovee owns

- the canonical Post identity and text;
- optional human-facing titles;
- application and source metadata;
- tags and tag assignments;
- the desired Tama target for each projection;
- synchronization lifecycle and audit events;
- the mapping from a local Post to a remote Tama Entity;
- authorization and product lifecycle when those features are introduced; and
- retry and reconciliation policy.

### Tama owns

- Spaces and Classes;
- Entity validation and processing;
- Concepts and execution lineage;
- chunking;
- embeddings and vector dimensions;
- embedding and reranking processors;
- model configuration; and
- generated semantic output.

Tama currently persists concept chunks and embeddings but does not expose a
public chunk API, vector-search API, or Entity deletion endpoint. Memovee must
not create a second canonical vector store merely to work around those API
gaps. Retrieval should eventually be exposed by Tama or implemented as an
explicitly disposable search projection.

## Terminology

### Post

A Post is the canonical memory input controlled by Memovee. Its body is the
dense text supplied for Tama processing and embedding generation.

### Tag namespace

`Tag.namespace` is a taxonomy category such as `topic`, `project`, or
`memory`. It is not a Tama Space and does not identify an authorization or
tenant boundary.

### Projection

A Projection is the synchronization relationship between one canonical Post
and one Tama target. It answers:

- where the Post should be sent;
- which Tama Entity represents it;
- whether the current Post body is synchronized; and
- what happened during each synchronization attempt.

Projection is not a copy of the Tama Entity, Concept, chunks, or embeddings.

### Actor

An Actor is the Accounts-owned stable account principal responsible for an
Eventful transition. Credentials resolve to Actor but do not live on Actor.

## Data model overview

```text
Actor
  `-- has many Projection Events

Post
  |-- has many Taggings
  |-- has many Tags through Taggings
  `-- has many Projections

Tag
  |-- belongs to a semantic namespace through its namespace field
  `-- has many Posts through Taggings

Projection
  |-- belongs to Post
  `-- has many actor-attributed Events
```

## Accounts Actor

`Memovee.Accounts.Actor` is implemented as a credential-neutral principal in
the `actors` table. It contains only its UUIDv7 identity, `current_state`, and
microsecond UTC timestamps.

Actor starts in `active`; the database permits only `active` and `inactive`.
The public creation changeset does not cast lifecycle state. Authentication and
credential schemas will be added later and must always resolve back to this
stable Actor.

The following remain related Accounts schemas rather than Actor fields:

- username and profile;
- email and verification state;
- password hash and password history;
- provider and external subject identity;
- sessions and tokens; and
- roles and permissions.

This keeps Eventful attribution stable when credentials or profile data change.
Projection events reference `actors.id` with restricted deletion. Future
account erasure must remove or redact credentials and personal data while
retaining an inactive principal when audit history requires it.

## Post schema

Schema:

```text
Memovee.Memory.Post
```

Table:

```text
memory_posts
```

Proposed fields:

| Field | Ecto type | Database type | Required | Notes |
| --- | --- | --- | --- | --- |
| `id` | `Ecto.UUID` | `uuid` | yes | Monotonic UUIDv7 |
| `title` | `:string` | `varchar` | no | Optional display label |
| `body` | `:string` | `text` | yes | Canonical dense text |
| `body_hash` | `:string` | `varchar(64)` | yes | Lowercase SHA-256 hex digest |
| `metadata` | `:map` | `jsonb` | yes | Defaults to `{}` |
| timestamps | `:utc_datetime` | timestamp | yes | Project default |

Associations:

```elixir
has_many :taggings, Memovee.Memory.Tagging
has_many :tags, through: [:taggings, :tag]
has_many :projections, Memovee.Memory.Projection
```

### Body behavior

`body` is required and must contain at least one non-whitespace character. The
stored value remains byte-for-byte canonical. Validation may use a trimmed
value to detect blank input, but it must not replace the stored body with a
trimmed version.

`body_hash` is calculated programmatically from the exact stored body bytes:

```elixir
:sha256
|> :crypto.hash(body)
|> Base.encode16(case: :lower)
```

Clients must not cast or supply `body_hash`.

The hash is not globally unique. Two Posts may legitimately contain identical
text. Its purposes are change detection, synchronization reconciliation, and
avoiding unnecessary remote updates.

If the projected Tama record later includes title, tags, or selected metadata,
the design must add a deterministic `projection_hash` over that complete
payload. `body_hash` must not be silently redefined to mean different data.

### Fields intentionally omitted

- No embedding or vector field. Tama owns embeddings.
- No model or vector dimension. Tama owns processor configuration.
- No generated summary. Generated semantic output belongs to Tama Concepts.
- No token count until a concrete query or quota requires it.
- No `current_state` in the first version. Projection owns synchronization
  state, while Post remains canonical and editable.
- No creator foreign key yet. Post ownership and its relationship to the
  Accounts Actor will be decided with the Accounts model.

## Tag schema

Schema:

```text
Memovee.Memory.Tag
```

Table:

```text
memory_tags
```

Proposed fields:

| Field | Ecto type | Database type | Required | Notes |
| --- | --- | --- | --- | --- |
| `id` | `Ecto.UUID` | `uuid` | yes | Monotonic UUIDv7 |
| `namespace` | `:string` | `varchar` | yes | Semantic category |
| `key` | `:string` | `varchar` | yes | Stable machine key |
| `name` | `:string` | `varchar` | yes | Human display name |
| `description` | `:string` | `text` | no | Optional explanation |
| `metadata` | `:map` | `jsonb` | yes | Defaults to `{}` |
| timestamps | `:utc_datetime` | timestamp | yes | Project default |

Associations:

```elixir
has_many :taggings, Memovee.Memory.Tagging
has_many :posts, through: [:taggings, :post]
```

Constraints and indexes:

```text
UNIQUE(namespace, key)
INDEX(namespace)
```

Both `namespace` and `key` are normalized to lowercase before validation and
storage. The accepted machine format should be deliberately small, for
example:

```text
[a-z0-9][a-z0-9._-]*
```

Example identities:

```text
topic/elixir
topic/phoenix
project/memovee
project/tama
agent/researcher
memory/episodic
```

`name` is not independently unique. Two namespaces may use the same display
name, and one namespace may intentionally contain different machine keys with
similar labels.

There is no separate Namespace schema in this phase. If namespaces gain
ownership, permissions, lifecycle, or configuration, they should become a
first-class relation instead of accumulating those concepts inside Tag
metadata.

Projects and topics also remain tags initially. A Project should become its
own schema if it later owns authorization, billing, retention, agents, or Tama
configuration.

## Tagging schema

Schema:

```text
Memovee.Memory.Tagging
```

Table:

```text
memory_taggings
```

Proposed fields:

| Field | Ecto type | Database type | Required | Notes |
| --- | --- | --- | --- | --- |
| `id` | `Ecto.UUID` | `uuid` | yes | Monotonic UUIDv7 |
| `post_id` | `Ecto.UUID` | `uuid` | yes | FK to `memory_posts` |
| `tag_id` | `Ecto.UUID` | `uuid` | yes | FK to `memory_tags` |
| `inserted_at` | `:utc_datetime` | timestamp | yes | Assignment time |

Constraints and indexes:

```text
UNIQUE(post_id, tag_id)
INDEX(tag_id)
```

The composite unique index is also the post-leading lookup index, so a
standalone `post_id` index would be redundant.

Deletion behavior:

```text
post deletion -> cascade taggings
tag deletion  -> cascade taggings
```

Tagging has no `updated_at`, metadata, confidence, source, ordering, or
provenance in the first version. If machine-generated tagging is introduced,
its source, model, confidence, and generation version need an explicit design
rather than being added casually to this editorial join.

`post_id` and `tag_id` must be assigned programmatically by manager functions.
They must not be accepted through a general client-facing `cast/3` call.

## Projection schema

Schema:

```text
Memovee.Memory.Projection
```

Table:

```text
memory_projections
```

Proposed fields:

| Field | Ecto type | Database type | Required | Notes |
| --- | --- | --- | --- | --- |
| `id` | `Ecto.UUID` | `uuid` | yes | Monotonic UUIDv7 |
| `post_id` | `Ecto.UUID` | `uuid` | yes | Canonical local Post |
| `identifier` | `:string` | `varchar` | yes | Stable Tama Entity identifier |
| `tama_space_id` | `Ecto.UUID` | `uuid` | yes | External Tama Space ID |
| `tama_class_id` | `Ecto.UUID` | `uuid` | yes | External Tama Class ID |
| `tama_entity_id` | `Ecto.UUID` | `uuid` | no | Set after remote creation |
| `synced_body_hash` | `:string` | `varchar(64)` | no | Body version last completed |
| `current_state` | `:string` | `varchar` | yes | Eventful-governed state |
| `current_state_version` | `:integer` | integer | yes | Optimistic lock, default `0` |
| `metadata` | `:map` | `jsonb` | yes | Defaults to `{}` |
| timestamps | `:utc_datetime` | timestamp | yes | Project default |

The Tama IDs are typed UUID values but are not database foreign keys because
they identify rows in another service.

Associations:

```elixir
belongs_to :post, Memovee.Memory.Post
has_many :events, Memovee.Memory.Projection.Event
```

Constraints and indexes:

```text
UNIQUE(post_id, tama_space_id, tama_class_id)
UNIQUE(tama_space_id, tama_class_id, identifier)
UNIQUE(tama_entity_id) WHERE tama_entity_id IS NOT NULL
CHECK current_state IN ('pending', 'syncing', 'synced', 'failed')
CHECK current_state_version >= 0
INDEX(current_state)
INDEX(post_id)
INDEX(tama_space_id, tama_class_id)
```

The stable default Tama identifier is the Post UUID encoded as a standard UUID
string. It permits idempotent reconciliation without inventing a second local
identity.

The Projection changeset must not cast:

- `post_id`;
- `tama_entity_id`;
- `synced_body_hash`;
- `current_state`; or
- `current_state_version`.

Those values are assigned by manager or transition code.

## Eventful lifecycle

This lifecycle is implemented with `Memovee.Accounts.Actor` as the required
event actor. There are no actorless transitions or temporary status writes.

### Dependency

Use the same Eventful major version as current Tama:

```elixir
{:eventful, "~> 3.3"}
```

### Transitable schema

Projection follows Eventful's conventional schema setup:

```elixir
defmodule Memovee.Memory.Projection do
  use Memovee.Schema
  use Eventful.Transitable

  alias __MODULE__.Event
  alias __MODULE__.Transitions

  Transitions
  |> governs(:current_state,
    on: Event,
    lock: :current_state_version
  )

  schema "memory_projections" do
    field :identifier, :string
    field :tama_space_id, Ecto.UUID
    field :tama_class_id, Ecto.UUID
    field :tama_entity_id, Ecto.UUID
    field :synced_body_hash, :string
    field :current_state, :string, default: "pending"
    field :current_state_version, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :post, Memovee.Memory.Post

    timestamps()
  end
end
```

Eventful's generated `state_changeset/2` validates states from the registered
transition modules and applies optimistic locking when the governed field
changes.

Ordinary changesets must never update `current_state` directly. All lifecycle
changes go through `Eventful.Transit.perform/4`.

### State machine

```text
pending --sync------> syncing
syncing --complete--> synced
syncing --fail------> failed
failed  --retry-----> syncing
synced  --invalidate> pending
failed  --invalidate> pending
syncing --invalidate> pending
```

Transition meanings:

| Event | From | To | Meaning |
| --- | --- | --- | --- |
| `sync` | `pending` | `syncing` | Begin initial or invalidated synchronization |
| `complete` | `syncing` | `synced` | Tama accepted the current body version |
| `fail` | `syncing` | `failed` | The synchronization attempt failed |
| `retry` | `failed` | `syncing` | Retry a failed synchronization |
| `invalidate` | `synced` | `pending` | Canonical body changed after success |
| `invalidate` | `failed` | `pending` | Canonical body changed after failure |
| `invalidate` | `syncing` | `pending` | Canonical body changed during an attempt |

There is no `pending -> pending` invalidation event. Code should avoid writing
redundant audit events when a projection is already pending.

There is no direct `synced -> syncing` transition. A forced resynchronization
is represented by explicit `invalidate` followed by `sync`, preserving why the
resource stopped being current.

### Transition module

Follow Tama's module convention:

```elixir
defmodule Memovee.Memory.Projection.Transitions do
  @behaviour Eventful.Handler

  use Eventful.Transition, repo: Memovee.Repo

  alias Memovee.Memory.Projection
  alias Memovee.Memory.Projection.Manager

  Projection
  |> transition(
    [from: "pending", to: "syncing", via: "sync"],
    fn changes -> transit(changes) end
  )

  Projection
  |> transition(
    [from: "syncing", to: "synced", via: "complete"],
    fn changes -> Manager.complete_transition(changes) end
  )

  # Remaining ordinary transitions call transit/1.
end
```

`Transitions` contains declarations only. `Projection.Manager` owns the
focused completion helper that updates
`tama_entity_id` and `synced_body_hash` in the same Eventful transaction as the
state and event insert. The helper must validate transition parameters before
placing those values on the resource changeset.

The `fail` event should store the stable error category and bounded diagnostic
details in event metadata. Projection does not initially duplicate this data
into `attempts`, `last_error`, or `last_attempted_at` columns.

### Event schema

Schema:

```text
Memovee.Memory.Projection.Event
```

Table:

```text
memory_projection_events
```

Eventful configuration:

```elixir
defmodule Memovee.Memory.Projection.Event do
  alias Memovee.Accounts.Actor
  alias Memovee.Memory.Projection

  use Eventful,
    parent: {:projection, Projection},
    actor: {:actor, Actor},
    table_name: "memory_projection_events",
    binary_id: Memovee.Eventful.UUIDv7

  alias Projection.Transitions

  handle(:transitions, using: Transitions)
end
```

Eventful generates these event fields and associations:

| Field | Required | Notes |
| --- | --- | --- |
| `id` | yes | UUIDv7 through the Eventful ID adapter |
| `projection_id` | yes | Parent Projection |
| `actor_id` | yes | Actor responsible for the transition |
| `name` | yes | Event name such as `sync` or `fail` |
| `domain` | yes | Defaults to `transitions` in the protocol |
| `metadata` | yes | Changes, comment, and parameters |
| timestamps | yes | Eventful uses `utc_datetime_usec` |

Migration requirements:

```text
projection_id -> memory_projections.id ON DELETE RESTRICT
actor_id      -> actors.id ON DELETE RESTRICT
INDEX(projection_id)
INDEX(actor_id)
INDEX(name, domain)
```

Event rows are immutable audit records. Their restricted foreign keys mean a
Projection or Accounts Actor with event history cannot be hard-deleted
casually.

### Event metadata

Eventful metadata contains:

```text
changes
comment
parameters
```

Examples:

```elixir
Eventful.Transit.perform(projection, account_actor, "sync",
  parameters: %{
    body_hash: post.body_hash
  }
)
```

```elixir
Eventful.Transit.perform(projection, account_actor, "fail",
  comment: "Tama returned an unavailable response",
  parameters: %{
    reason: "tama_unavailable",
    status: 503
  }
)
```

```elixir
Eventful.Transit.perform(projection, account_actor, "complete",
  parameters: %{
    tama_entity_id: entity.id,
    body_hash: post.body_hash
  }
)
```

Comments and parameters must not contain credentials, full remote response
bodies, unbounded exception output, or Post body text.

### Transit protocol

Follow Tama's convention by implementing `Eventful.Transit` for Projection:

```elixir
defimpl Eventful.Transit, for: Memovee.Memory.Projection do
  alias Memovee.Memory.Projection.Event

  def perform(projection, actor, event_name, options \\ []) do
    domain = Keyword.get(options, :domain, "transitions")
    comment = Keyword.get(options, :comment)
    parameters = Keyword.get(options, :parameters, %{})

    Event.handle(projection, actor, %{
      domain: domain,
      name: event_name,
      comment: comment,
      parameters: parameters
    })
  end
end
```

The protocol deliberately does not reload Projection. Reloading would discard
the caller's `current_state_version` and weaken optimistic-lock protection of
caller intent.

## Eventful UUIDv7 compatibility

Eventful has a `binary_id` option and it must be used. The nuance is how that
option generates IDs.

Using:

```elixir
binary_id: true
```

causes Eventful 3.3 to define:

```elixir
@primary_key {:id, :binary_id, autogenerate: true}
@foreign_key_type :binary_id
```

Ecto SQL handles `:binary_id` autogeneration by calling:

```elixir
Ecto.UUID.bingenerate()
```

with no options. That defaults to UUIDv4 and violates Memovee's monotonic
UUIDv7 convention.

Eventful also accepts a custom Ecto type through `binary_id`. Tama currently
uses the third-party `UUIDv7` type this way. Memovee has already standardized
on Ecto 3.14's native UUIDv7 support and should not add another UUID dependency
for Eventful alone.

Add a small compatibility type:

```elixir
defmodule Memovee.Eventful.UUIDv7 do
  use Ecto.Type

  def type, do: :uuid

  defdelegate cast(value), to: Ecto.UUID
  defdelegate dump(value), to: Ecto.UUID
  defdelegate load(value), to: Ecto.UUID

  def autogenerate do
    Ecto.UUID.generate(version: 7, precision: :monotonic)
  end
end
```

Then configure Eventful with:

```elixir
binary_id: Memovee.Eventful.UUIDv7
```

This still uses Eventful's supported `binary_id` option. The compatibility
type only supplies the zero-arity `autogenerate/0` callback that Eventful's
macro requires. Database columns remain PostgreSQL `uuid`, and generated IDs
remain RFC 9562 UUIDv7 with monotonic precision.

Normal application schemas continue to `use Memovee.Schema` and use
`Ecto.UUID` directly. Eventful-generated Event schemas are the documented
exception because Eventful owns their `Ecto.Schema` declaration.

The project Ecto guidelines must be updated to record this exception before
implementation is considered complete.

## Synchronization flow

Tama HTTP calls must not execute inside an Eventful database transaction.
Eventful transitions record lifecycle boundaries; they are not wrappers around
long-running network operations.

### Initial synchronization

1. Load the Projection, Post, and authenticated Accounts Actor.
2. Capture the Post `body_hash` and body.
3. Perform the `sync` transition.
4. Send the Tama request outside the Eventful transaction.
5. Use the Post UUID string as the Tama Entity identifier.
6. Reload the Post and Projection after Tama responds.
7. If the Post hash changed, perform `invalidate` rather than `complete`.
8. If the hash is unchanged, perform `complete` with the Entity ID and captured
   body hash.
9. If Tama fails, perform `fail` with a stable atom reason that is recorded as
   an Eventful parameter.

### Retry

1. Load a failed Projection and the Accounts Actor attributed to the retry.
2. Perform `retry`.
3. Reconcile using the stable Tama identifier before blindly creating another
   Entity.
4. Update the known remote Entity when possible.
5. Complete or fail through Eventful.

Tama may successfully create an Entity while Memovee fails to persist the
completion event. Retry logic must therefore be idempotent and able to recover
the Entity by stable identifier or from a conflict response.

### Post update and invalidation

When a Post body changes:

1. Validate and update the canonical Post.
2. Recalculate `body_hash` from the exact new body.
3. Load non-pending Projections for the Post.
4. Perform `invalidate` for each Projection using the Actor responsible for the
   Post update.
5. Leave already-pending Projections unchanged.

The implementation wraps the Post update and all invalidations in an outer
`Ecto.Multi`. Eventful's transition transactions are nested on the same Repo
checkout, so a failed invalidation rolls the Post update and earlier
invalidations back together. Projections are processed in UUIDv7 order to keep
lock acquisition deterministic.

A Projection is current only when both conditions hold:

```text
current_state == "synced"
synced_body_hash == post.body_hash
```

Pending-work queries and API representations must apply this rule. A hash
mismatch prevents concurrent lifecycle activity from presenting stale remote
content as current. Reconciliation can later repair the lifecycle state.

### Concurrent update during synchronization

If a Post changes while its Projection is syncing:

- the update path may transition the Projection from `syncing` to `pending`;
- the worker must reload both records after the remote request;
- a worker holding the old body hash must not complete the new version;
- optimistic locking rejects stale state writes; and
- the stable identifier allows the next attempt to update the same Tama Entity.

## Context API

Initial Post API:

```elixir
Memovee.Memory.create_post(attrs)
Memovee.Memory.update_post(actor, post, attrs)
Memovee.Memory.get_post!(id)
Memovee.Memory.list_posts(opts \\ [])
```

The actor-aware update function atomically updates the Post and invalidates its
non-pending Projections. There is intentionally no public actor-free update
function that could bypass Projection invalidation.

Initial Tag API:

```elixir
Memovee.Memory.create_tag(attrs)
Memovee.Memory.update_tag(tag, attrs)
Memovee.Memory.get_tag!(id)
Memovee.Memory.get_tag_by_namespace_and_key(namespace, key)
Memovee.Memory.list_tags(opts \\ [])
Memovee.Memory.upsert_tag(attrs)
```

Initial Tagging API:

```elixir
Memovee.Memory.tag_post(post, tag)
Memovee.Memory.untag_post(post, tag)
Memovee.Memory.list_post_tags(post)
Memovee.Memory.list_posts_by_tag(tag, opts \\ [])
```

Initial Projection API:

```elixir
Memovee.Memory.create_projection(post, attrs)
Memovee.Memory.get_projection!(id)
Memovee.Memory.list_post_projections(post)
Memovee.Memory.list_pending_projections()
Memovee.Memory.start_projection_sync(actor, projection)
Memovee.Memory.complete_projection_sync(actor, projection, attrs)
Memovee.Memory.fail_projection_sync(actor, projection, reason)
Memovee.Memory.retry_projection_sync(actor, projection)
Memovee.Memory.invalidate_projection(actor, projection)
```

The lifecycle wrappers call `Eventful.Transit.perform/4`; they never update
`current_state` directly.

Manager functions assign relationship IDs programmatically and enforce the
global data boundary. Aggregate contexts delegate to those managers. When
workspace or agent scoping is added, scope arguments and query filters must be
introduced at the context and manager boundary rather than only in controllers.

## Query behavior

### Post listing

Post list queries should preload tags only when the caller requests or renders
them. They must not trigger one tag query per Post.

UUIDv7 supports deterministic keyset pagination:

```text
ORDER BY id DESC
WHERE id < cursor
```

Offset pagination is unnecessary for the initial API.

### Tag lookup

Namespace and key normalization must happen before lookup. The database unique
constraint remains the final concurrency boundary for upsert behavior.

### Projection work selection

A Projection is selected as ordinary pending work when either condition is
true:

```text
current_state == "pending"
OR (current_state == "synced"
    AND synced_body_hash IS DISTINCT FROM post.body_hash)
```

Failed rows are retried through explicit retry policy rather than being mixed
silently into ordinary pending work.

Rows stuck in `syncing` require a future lease or watchdog design. Eventful
history can show when synchronization began, but this phase does not yet define
worker leasing or automatic timeout recovery.

## Migration plan

The migrations were created in dependency order:

1. `create_actors`
2. `create_memory_posts`
3. `create_memory_tags`
4. `create_memory_taggings`
5. `create_memory_projections`
6. `create_memory_projection_events`

Use `mix phx.gen.schema` as the starting point for persisted schemas and
`mix ecto.gen.migration` for Eventful's event table or later migration-only
changes. Generated files must then be adapted for constraints, indexes,
Eventful modules, and changeset security.

Every table uses an explicit `:binary_id` primary-key column in its migration.
Every local foreign key uses `type: :binary_id`.

Eventful's event schema timestamps are `:utc_datetime_usec`, so the event
migration must also use microsecond UTC timestamps even though the current
Memovee generator defaults ordinary schemas to `:utc_datetime`.

Do not add `citext` solely for this model. Normalize Tag namespace and key in
application code and enforce their composite uniqueness with ordinary strings.

Do not add GIN indexes on metadata until an actual query requires them.

## Testing plan

### Schema tests

- Post requires a nonblank body.
- Post preserves the exact body value supplied by the caller.
- Post calculates the expected lowercase SHA-256 body hash.
- Updating body changes the hash.
- Updating title or metadata alone does not change the body hash.
- Tag normalizes namespace and key.
- Tag rejects invalid machine-key formats.
- Relationship IDs are not accepted through public changeset casts.

### Constraint tests

- Tag namespace and key are unique together.
- Tagging post and tag are unique together.
- A Post and Tama target have only one Projection.
- Tama Entity identifiers are unique within Space and Class.
- Non-null Tama Entity IDs are unique.
- Tagging deletion cascades with Post and Tag deletion.
- Event foreign keys enforce the agreed Projection and Accounts Actor deletion
  policies.
- Database checks reject invalid Projection states.

### Eventful tests

These tests require the migrated test database.

- Every declared transition succeeds from its valid source state.
- Every undeclared transition returns an Eventful error.
- State and event insert commit in one transaction.
- A failed event insert rolls back the state update.
- Event metadata records state changes.
- Event metadata preserves bounded comments and parameters.
- Every event has an Accounts Actor.
- `current_state_version` rejects stale concurrent transitions.
- Ordinary Projection changesets cannot alter lifecycle state.
- Event IDs are UUIDv7.
- Multiple immediately generated event IDs are strictly monotonic.
- Event IDs persist and load through PostgreSQL UUID columns.

### Synchronization tests

These tests require the migrated test database.

- Starting sync records a `sync` event attributed to an Accounts Actor.
- Completion stores Tama Entity ID and the synchronized body hash.
- Failure records a sanitized reason without storing credentials or body text.
- Retry uses the same stable Tama identifier.
- A Post update invalidates synced Projections.
- A body update during sync prevents stale completion.
- Hash mismatch is treated as stale even if invalidation event creation fails.
- Failed Projections are not retried without an explicit retry transition.
- A remote success followed by local failure can be reconciled without creating
  a duplicate Tama Entity.

### Context tests

- Tagging is idempotent under the unique constraint.
- Tag removal does not delete the Tag itself.
- Post list operations can preload tags without N+1 queries.
- Pending Projection listing includes hash-mismatched rows.

These persisted tests should use `Memovee.DataCase`. Running them requires a
created and migrated test database. The repository was initially generated in
configuration-only mode, so database creation must be explicitly approved when
database integration verification starts.

## Implementation status

Implemented:

1. Credential-neutral Accounts Actor and migration.
2. Post, Tag, Tagging, and Projection schemas and migrations.
3. Exact Post body hashing and Tag identity normalization.
4. Database constraints, indexes, and deletion policies.
5. Eventful 3.3 dependency and monotonic UUIDv7 compatibility type.
6. Projection Event, Transitions, Transit protocol, and event migration.
7. Optimistic state versioning and actor-attributed lifecycle wrappers.
8. Transactional completion that verifies the current Post body hash before
   recording Tama Entity ID and synchronization hash.
9. Actor-aware Post updates with atomic invalidation of non-pending
   Projections.
10. Pending-work selection that detects stale synced hashes without implicitly
    retrying failed Projections.
11. Stable atom failure reasons recorded without arbitrary inspected error
    data.
12. Database-free unit coverage for schema behavior, transition declarations,
    and Eventful UUIDv7 configuration.
13. Tama-style per-schema Manager modules, thin context delegates, and a
    declaration-only Projection Transitions module.

Remaining before the persistence layer is considered verified:

1. Obtain approval to create and migrate the test database.
2. Add DataCase coverage for constraints, event transactions, optimistic
   locking, and concurrent Post changes.
3. Finalize Accounts credentials, authentication, and current-Actor resolution.
4. Decide how background synchronization is attributed when no request Actor is
   active.
5. Add a synchronization worker and Tama client reconciliation.
6. Run the complete precommit suite against PostgreSQL.

A production synchronization worker and UI remain separate work.

## Failure and recovery behavior

- Invalid transitions return Eventful errors and do not update Projection.
- Remote transport failures transition `syncing` to `failed` when possible.
- Failure parameters contain only a stable reason string derived from an atom.
- If recording failure itself fails, the Projection may remain `syncing` and
  must be recoverable by a future watchdog.
- If Tama succeeds but local completion fails, retry reconciles by identifier.
- If a Post changes during a request, the old body must not be marked current.
- A hash mismatch is always stale regardless of `current_state`.
- No network call is made while holding an Ecto transaction open.

## Deletion and retention

Tama currently has no public Entity deletion endpoint. Hard-deleting a local
Post could orphan a remote Entity. Eventful events also intentionally restrict
deletion of their Accounts Actor and Projection according to the eventual
Accounts policy.

The first public context should therefore omit `delete_post/1` and
`delete_projection/1`.

A later design must choose among:

- remote deletion followed by local deletion;
- soft deletion and tombstones;
- archival without remote removal; or
- retention expiration with a reconciliation process.

Event retention also needs an explicit policy. Projection events are initially
kept indefinitely because they are the synchronization audit log. If pruning
is introduced, the latest completion and failure history required for
operations must be retained deliberately.

## Security considerations

- Never cast local relationship IDs from untrusted attributes.
- Never put Tama credentials in Post, Projection, or event metadata.
- Never store Post body text in Eventful metadata.
- Bound transition comments and parameter sizes.
- Normalize remote errors into stable categories.
- Treat external Tama UUIDs as untrusted input and cast them through Ecto.UUID.
- Keep Eventful state transitions behind the Memory context API.
- Add scope filtering to every context query when ownership is introduced.

## Observability considerations

Eventful events provide durable lifecycle history, but runtime telemetry should
eventually include:

- sync attempt count;
- sync duration;
- completion and failure count by stable reason;
- stale Projection count;
- rows stuck in `syncing`;
- retry count;
- Tama response status distribution; and
- local completion failures after remote success.

Do not infer all operational metrics from unbounded event scans at high volume.
Add purpose-built telemetry or projections once actual load requires them.

## Non-goals

- Persisting embeddings in Memovee.
- Implementing vector search in Memovee.
- Copying Tama Concepts or chunks into canonical Post fields.
- Designing workspaces or multi-tenancy in this phase.
- Making Project or Topic first-class schemas.
- Adding machine-tagging confidence or provenance.
- Adding Post version history.
- Implementing hard deletion.
- Adding an Oban worker before synchronization behavior is finalized.
- Performing Tama HTTP calls from Eventful transition transactions or
  triggers.
- Replacing Tama Spaces or Classes with Tag namespaces.
- Designing credential, authentication, or profile schemas as part of the
  Memory workstream.

## Open decisions

- Whether the first Tama payload contains only `body` or also includes title
  and selected metadata.
- The exact Tama Class schema used for projected Posts.
- Whether Memovee initially targets one configured Tama Space and Class or lets
  callers select targets.
- How a Projection reconciles an Entity after remote success and local failure
  with the currently available Tama client API.
- Whether a dedicated connection schema is needed before supporting multiple
  Tama deployments.
- Which queue system will run synchronization and how jobs will be deduplicated.
- The retry backoff, maximum attempts, and terminal failure policy.
- The lease or watchdog policy for Projections stuck in `syncing`.
- Whether Eventful history is retained indefinitely or pruned under a bounded
  policy.
- The future Post deletion and Tama tombstone contract.
- When Project, Workspace, Agent, and User ownership become first-class foreign
  keys rather than global records or tags.
- How Accounts attributes automated synchronization and retries when no user is
  actively making a request.

## Acceptance criteria

### Foundational model

- Post, Tag, Tagging, and Projection schemas use monotonic UUIDv7.
- Their database constraints and indexes are covered by tests.
- Post body hashing is deterministic and does not mutate canonical text.
- Tag identity is normalized and unique by namespace and key.
- Projection identity mirrors Tama's Space, Class, and identifier boundary.
- Projection starts in `pending` without exposing direct lifecycle mutation.
- Actor contains no credential or profile fields.
- No embeddings or synthetic system Actor are added.
- All foundational checks pass without warnings.

### Persistence and synchronization

- Accounts Actor exists and is the required Eventful actor relation.
- Eventful 3.3 compiles with Ecto 3.14 and Elixir 1.20.3.
- Eventful event IDs are proven monotonic UUIDv7.
- Actor attribution is present on every Projection event.
- Projection and Event constraints are covered by tests.
- No public changeset can directly modify Projection lifecycle state.
- A completed Projection records the exact Post body hash it synchronized.
- Stale content cannot be reported as current after a concurrent Post update.
- Retry is idempotent against Tama's stable Entity identifier.
- No embeddings or credentials are duplicated into Memory records or events.
- All persistence and synchronization checks pass without warnings.
