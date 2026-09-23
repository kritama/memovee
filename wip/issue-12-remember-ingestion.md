# Issue #12: Remember ingestion

Status: Implemented in source; plan reviewed; not applied, restarted, or live-accepted

Branch: `feature/issue-12-remember-ingestion`

Baseline: `fab292b` (`ghcr.io/upmaru/tama:0.15.0-server`)

Tracking:

- [kritama/memovee#12](https://github.com/kritama/memovee/issues/12)
- [kritama/memovee#13](https://github.com/kritama/memovee/issues/13), which owns
  asynchronous enrichment and indexing
- [upmaru/tama#128](https://github.com/upmaru/tama/issues/128), resolved by
  [upmaru/tama#129](https://github.com/upmaru/tama/pull/129)

## Purpose

Implement the production `remember` graph so one user message can be converted
into either:

- one idempotent `POST /tama/memory/posts` operation and a durable save receipt,
- one clarification question with no write, or
- one explicit, schema-valid failure result.

The graph must use `tama/agentic/tooling` for both argument generation and action
execution. It must forward every terminal component result to the existing root
`tama/agentic/result` stage, which publishes the forwarded concept as the
thread's durable terminal result.

Saving and indexing are deliberately separate. A successful Post transaction
creates durable indexing work and returns a receipt whose indexing status may be
`pending`. Issue #13 delivers the canonical Post to Tama as a revision-specific
entity. Tama then follows the established `movie-details` pattern: generate a
description, embed the generated concept, and invoke one Memovee indexing action
after the entity is processed. Remember does not wait for that background flow.

This document is the implementation authority for issue #12's graph topology,
retry ownership, and migration sequence. Repository instructions and documented
project conventions supersede this WIP whenever they conflict. The application
request/response schemas remain authoritative for the HTTP wire contract. The
issue remains authoritative for product behavior and fixture intent except where
its older candidate/status/retry-save design conflicts with the decisions below.

## Scope

### In scope

- Enable the existing root `remember-forward` handoff into `memory-write`.
- Implement the `memory-write` component around `tama/agentic/tooling`.
- Bind Tooling to the imported `memory_post_create` action.
- Inject trusted actor and origin values with thought tool modifiers.
- Route the persisted Tooling request/response messages deterministically.
- Produce saved, clarification-required, and failed terminal results matching
  `RememberResultPublication`.
- Forward each terminal result to the existing root result publication request.
- Remove the obsolete candidate, status lookup, and graph-level retry-save
  topology.
- Add native Terraform topology/policy tests and fixture-backed behavior tests.
- Preserve Terraform state safely while replacing the disabled graph skeleton.

### Out of scope

- Changing the `/tama/memory/posts` controller or its idempotency model.
- Adding a save-status endpoint.
- Adding a new normalized Tooling outcome to Tama.
- Adding another retry loop around Tooling.
- Implementing the asynchronous entity-delivery, enrichment, embedding, and
  indexing pipeline from issue #13.
- Implementing `/tama/memory/index`; #12 only preserves the durable work created
  with the Post.
- Implementing recall.
- Applying Terraform or deploying/restarting Tama without separate approval.
- Enabling the test-only result fixture path in production.

## Resolved design conflicts

| Topic | Authoritative decision |
| --- | --- |
| Save execution | `tama/agentic/tooling` generates the arguments and executes `memory_post_create`. There is no Generate candidate followed by a deterministic Caller. |
| Save recovery | Tooling owns one bounded retry of the exact prepared POST through Tama's shared action executor. There is no status lookup or `remember-retry-save` stage. |
| Req behavior | Tama disables Req's implicit retry for Tooling execution. Retry count, retryable methods, and retryable response codes are explicit Tooling configuration. |
| `consecutive_limit` | It is graph configuration and is set to `2`; it is not a missing Tama runtime capability. |
| Pre-save normalization | There is no standalone pre-save Render stage, candidate class, or generic provider-response wrapper. Handler-local deterministic rendering may still construct schema-valid terminal results. |
| Unknown save outcome | `RememberResultPublication` has no `save_unconfirmed` outcome. Represent it as `outcome: "failed"` with `error.code: "save_unconfirmed"` and `retryable: true`. The text must not claim that the remote write failed. |
| Tool selection | The model may call exactly one external save tool or the existing internal `memo` tool. Set `parallel_tool_calls` to `false` and require a tool call. |
| Response selection | Select the actual persisted tool response by tool identity and tool-call correlation. Do not rely on an arbitrary message position. |
| Indexing handoff | The successful Post transaction creates durable indexing work. Its worker later creates a canonical, revision-specific Post entity in Tama; it must not call Tama inside the Post database transaction. |
| Indexing topology | Match `upmaru/memovee-tama`'s `movie-details` shape: source entity -> generated description -> `tama/concepts/embed` -> processed-entity index Caller. Memovee's `/tama/memory/index` replaces Elasticsearch as the final backend. |
| Projection APIs | Do not add `/tama/memory/projections/snapshot` or `/tama/memory/projections/complete`. The entity record is the snapshot; `/tama/memory/index` is the only completion/index sink. |
| Overall readiness | Completing remember does not complete recall. Do not change the repository-wide `ready` output to `true`; expose remember-specific completion only if useful. |
| Runtime version | The implementation targets Tama `0.15.0`, which contains the bounded recovery delivered for #128. |

## Existing contracts

### Application endpoint

Tooling calls:

```text
POST /tama/memory/posts
operationId: memory_post_create
```

The request body is:

```json
{
  "context": {
    "actor_id": "trusted actor identifier",
    "origin_identifier": "trusted origin entity identifier"
  },
  "post": {
    "title": "optional title",
    "body": "required memory body",
    "metadata": {},
    "tags": []
  }
}
```

The model owns `post` and must emit the required `context` parent object. It
must not be trusted to supply the two context leaf values. Thought tool
modifiers overwrite those leaves from Tama metadata before the action is
materialized.

The response is `{"data": {..., "receipt": receipt}}`. A receipt contains:

- `post_id`
- `body_hash`
- `tag_ids`
- `indexing_status`
- `replayed`

The endpoint returns `201` for a newly created post and `200` when the existing
post is replayed. Application idempotency is scoped by owner and
`origin_identifier`; a replay returns the current receipt.

The successful create transaction also creates one pending
`Memovee.Projections.Indexing` record and one Oban job. That durable job is the
handoff to issue #13. The HTTP request must not synchronously create a Tama
entity after the database commit and then reinterpret an entity-delivery failure
as a failed Post save.

### Asynchronous indexing boundary

Issue #13 must implement this separate background path:

```text
pending Memovee indexing job
  -> create or recover a canonical memory-post entity in Tama
  -> reactive description generation
  -> tama/concepts/embed
  -> memory-post entity reaches processed
  -> reactive deterministic Caller
  -> /tama/memory/index
  -> Memovee persists the searchable projection and marks it ready
```

This is the memory equivalent of the `movie-details` enrichment and indexing
pipeline in `upmaru/memovee-tama`; Memovee's index operation replaces the final
Elasticsearch action.

The Tama entity carries the complete canonical indexing input, so a snapshot
callback is unnecessary. Its identifier must be deterministic and
revision-specific, for example:

```text
memory-post:<post_id>:<revision>:<indexing_version>
```

Its record must include the Post ID, owner ID, revision, fingerprint,
`indexing_version`, title, body, typed metadata, and canonical tags. A delivery
retry must find or recover the same entity rather than creating a second source
entity.

The sole application callback is an idempotent `memory_index_upsert` action at
`/tama/memory/index`. It receives the stable Post/revision/fingerprint identity
plus the generated description and embedded chunks. Memovee rejects stale
revision or fingerprint values and treats the same
`(post_id, revision, indexing_version)` payload as a replay. Only a successful
index write can move the projection to ready.

Do not provision or call these obsolete operations:

- `memory_projection_snapshot`
- `memory_projection_complete`

The #13 implementation decides whether to use Tama's processor-configured
`TextChunker` exactly like `movie-details` or to place application-defined
deterministic chunks in the source entity. It must not reintroduce a snapshot
endpoint merely to obtain those chunks.

### Result contract

Every production terminal must conform to
`tama/graph/schemas/memory-contract.v1.json` and use one of these forms:

```json
{
  "operation": "remember",
  "outcome": "saved",
  "post_id": "uuid",
  "indexing_status": "pending",
  "replayed": false,
  "text": "Memory saved."
}
```

```json
{
  "operation": "remember",
  "outcome": "clarification_required",
  "question": "What should I remember?",
  "candidates": [],
  "text": "I need one clarification before saving this."
}
```

```json
{
  "operation": "remember",
  "outcome": "failed",
  "error": {
    "code": "save_unconfirmed",
    "message": "The save result could not be confirmed.",
    "retryable": true
  },
  "text": "I could not confirm whether the memory was saved."
}
```

Do not add a fourth top-level outcome without first changing the schema and its
consumers.

### Result publication

The root graph already contains the production terminal handoff:

```text
remember-result-publication-request
  -> tama/agentic/result
```

`tama/agentic/result` validates and publishes the existing forwarded concept.
It does not render or create a replacement concept. The implementation must
forward the component's schema-valid terminal concept to that request.

## Target graph

```text
root remember user message
  -> Forward to memory-write
  -> Agentic.Tooling
       -> memory_post_create
            -> HTTP 200/201 -> saved result
            -> transport code 0 -> save_unconfirmed failed result
            -> other HTTP code -> failed result
       -> memo
            -> clarification_required result
       -> invalid/missing/unmatched response
            -> invalid_tool_result failed result
  -> Forward terminal component result to root result-publication request
  -> tama/agentic/result
```

The Tooling response includes the generated and persisted messages. Routing
must inspect the correlated tool call and tool response, not merely the last
map or a fixed list index. With `parallel_tool_calls: false`, exactly one tool
call is expected.

## Tooling configuration

Use the Tooling module parameters supported by Tama 0.15.0.

### Model behavior

- `tool_choice`: `"required"`
- `parallel_tool_calls`: `false`
- `consecutive_limit`: `2`
- The available tools are the imported `memory_post_create` action and the
  existing internal `memo` tool.
- The prompt must instruct the model to preserve the user's original content as
  the memory corpus, produce one valid nested request, or ask one focused
  clarification question.
- Do not use client detection or provider-specific response assumptions.

`consecutive_limit` bounds model/tool continuation. It is separate from the
HTTP retry count below.

### Model continuation

Use Tooling's model-continuation retry for invalid tool arguments where the
runtime supports it:

```hcl
retry_on_codes = [422]
```

This allows the model to correct invalid arguments within the configured
consecutive limit. It must not cause a second external save after a valid
action request has been prepared.

### HTTP recovery

Configure the one exact-request retry delivered by upmaru/tama#128:

```hcl
capture_transport_errors  = true
retry_methods             = ["post"]
http_retry_on_codes       = [0, 408, 429, 500, 502, 503, 504]
max_http_retries          = 1
retry_delays_ms            = [0]
honor_retry_after_max_ms  = 5000
```

Required properties:

- The retry reuses the same prepared action, request body, origin identifier,
  and tool-call identity.
- The source rate limiter is consulted for every HTTP attempt.
- Tooling persists the final actual HTTP response.
- If both attempts end in an uncertain transport failure, Tooling persists code
  `0` with safe transport error information.
- No graph node issues a second independent save request.

### Trusted modifiers

Attach both modifiers to the exact `memory_post_create` thought tool:

| Index | Target | Metadata source | Missing metadata | Missing target |
| ---: | --- | --- | --- | --- |
| 0 | `/body/context/actor_id` | `actor_identifier` | error | error |
| 1 | `/body/context/origin_identifier` | `origin_entity_identifier` | error | error |

Inspect the imported action schema during implementation and verify that these
JSON pointer targets match the generated action input. A missing or spoofed
trusted value must fail before any HTTP request is sent.

## Terminal routing

### External save tool

First validate that the response belongs to the single assistant tool call for
the bound `memory_post_create` action.

- `200` or `201`: decode the response content, select `data.receipt`, and emit
  `outcome: "saved"`. Copy only contract fields. Preserve `replayed` and the
  returned `indexing_status`.
- `0`: emit `outcome: "failed"`, `error.code: "save_unconfirmed"`, and
  `retryable: true`. Use safe wording because the remote server may have
  committed before the connection failed.
- Any other real HTTP status: emit `outcome: "failed"` with a stable sanitized
  error code/message and an accurate retryability flag. Never copy secrets or
  unbounded remote response content into the public result.
- A malformed success response, mismatched call ID, or wrong tool identity:
  emit `outcome: "failed"` with `error.code: "invalid_tool_result"` and
  `retryable: false`.

### Memo tool

Accept only a correlated memo response with:

- target `response`,
- reason `clarification_required`, and
- a nonblank question no longer than 400 characters.

Emit `outcome: "clarification_required"`. No external action may have run on
this path.

### Missing or invalid tool call

A missing call, multiple calls, an unknown tool, or an uncorrelated response is
an explicit `invalid_tool_result` failure. It must not be interpreted as a save
receipt or silently dropped.

### Terminal construction

Handler-local corpus and Render stages may deterministically construct the
three schema-valid result shapes. They must not recreate the removed generic
candidate/provider-wrapper normalization pipeline. Every terminal path must
join the same component result and forward it to the root publication request.

## Implementation sequence

### Phase 1: freeze the current state shape

1. Run `terraform -chdir=tama state list` against the intended workspace when
   credentials are available.
2. Record existing resource addresses for the disabled remember handlers,
   chains, classes, bridges, and nodes.
3. Keep an address unchanged when moving a resource between files.
4. Add `moved` blocks for any necessary Terraform label rename.
5. Do not apply during this phase.

The current state may own remote resources for obsolete candidate, status, and
retry-save handlers. Removing their configuration is a real destroy operation,
even though their nodes are disabled.

### Phase 2: implement the component before enabling entry

1. Add `tama/graph/memory-write/tooling.md` beside its owning
   `memory-write.tf` file.
2. Remove the stale `memory-candidate-provider` class and implement the Tooling
   module/reference in `tama/graph/memory-write.tf`.
3. Bind the imported `memory_post_create` action and internal memo tool.
4. Add the two trusted thought tool modifiers.
5. Implement deterministic routing in the existing handler files:
   - `remember-save.tf`
   - `remember-receipt.tf`
   - `remember-clarification.tf`
   - `remember-failure.tf`
   - `remember-save-unconfirmed.tf`
   - `remember-invalid-response.tf`
6. Forward all component terminals to the existing root result publication
   request.
7. Keep production component and root entry nodes disabled until all topology
   and policy tests pass.

### Phase 3: remove obsolete topology

Remove:

- `tama/graph/remember-candidate.tf`
- `tama/graph/remember-invalid-candidate.tf`
- `tama/graph/remember-status.tf`
- `tama/graph/remember-retry-save.tf`
- any remaining candidate/status/retry-save classes, paths, corpora, and output
  stage names with no consumer.

Keep `remember-result-fixture.tf` as a test-only root-result regression path
until the real path is proven. It must remain gated by
`enable_result_fixtures` and disabled in production.

Update `tama/graph/outputs.tf` and the stage inventory assertions in the same
change. The old count of 31 stages is not a contract.

### Phase 4: enable the complete path

1. Enable the `memory-write` component node only after every terminal route is
   connected.
2. Enable the root `remember-forward` node only after the component can always
   terminate or fail explicitly.
3. Confirm the bridge directions and chain targets are unchanged.
4. Keep the repository-wide `ready` output false while recall remains
   incomplete. Add a separate remember-ready output only if operators need it.

### Phase 5: plan and deploy separately

1. Let Terraform fetch the real memory API OpenAPI document from
   `https://app.localhost/tama/openapi` and register it with
   `tama_specification`, following `memovee-tama/interface.tf`. On a local Tama
   state where the specification was already created outside Terraform, reuse
   its adopted `module.memory.tama_specification.memory_api` state address; do
   not import it again. Keep the specification
   endpoint at the document URL; Tama derives the API source endpoint from the
   OpenAPI `servers` entry. Set the specification version to the Memovee app
   version in `mix.exs`, not the OpenAPI format version.
2. Wait for the Terraform-managed specification to become complete.
3. Configure the `bearer_auth` source identity with an Agent API token. The
   write endpoint permits context Actors under the same active user owner as
   that Agent; there is no single-Actor environment allowlist. A shared source
   identity cannot serve Actors owned by different users. Tama 0.15.0 needs
   the imported OpenAPI to describe an
   `Authorization` header API key with `x-bearer-format: bearer`; its identity
   `api_key` is `<client-id>.<client-secret>`, not separate OAuth credential
   fields. Validate with authenticated `GET /tama/health`, which accepts any
   active Agent API credential; writes additionally require same-owner context
   authorization and structured post validation. Verify
   verify the imported operation is exactly `memory_post_create`. Make the
   remember tool wait for an active identity before it can be provisioned.
4. Set the source slug, operation set, `memory_api_client_id`, and sensitive
   `memory_api_client_secret` variables without committing secrets. Protect
   Terraform state and saved plans, which can contain the credential.
5. Run a Terraform plan and review every create, update, replacement, and
   delete. Pay particular attention to removed disabled handlers.
6. Apply only with explicit approval.
7. Restart or recreate Tama after graph/queue provisioning because queues are
   loaded at boot.
8. Run live fixture acceptance and inspect runtime traces.

## Expected file changes

### Update

- `tama/graph/remember.tf`
- `tama/graph/memory-write.tf`
- `tama/graph/memory-api.tf` to bind only `memory_post_create` for #12 and remove
  the obsolete projection operation names from the shared allowlist; the future
  #13 operation is `memory_index_upsert`
- `tama/graph/remember-save.tf`
- `tama/graph/remember-receipt.tf`
- `tama/graph/remember-clarification.tf`
- `tama/graph/remember-failure.tf`
- `tama/graph/remember-save-unconfirmed.tf`
- `tama/graph/remember-invalid-response.tf`
- `tama/graph/outputs.tf`
- `tama/tests/foundations.tftest.hcl`
- graph README/documentation that still describes the old topology or Tama
  version

### Add

- `tama/graph/memory-write/tooling.md`
- `tama/graph/memory-write/remember-tool-result.liquid`
- `tama/graph/remember-save/remember-save-result.liquid`
- `tama/graph/remember-clarification/remember-clarification-result.liquid`
- `tama/graph/remember-invalid-response/remember-invalid-response-result.liquid`
- native Terraform tests for the production topology and Tooling policy
- `test/tama/remember_corpora_test.exs` for automated deterministic corpus fixtures

### Remove

- `tama/graph/remember-candidate.tf`
- `tama/graph/remember-invalid-candidate.tf`
- `tama/graph/remember-status.tf`
- `tama/graph/remember-retry-save.tf`

Every single-owner prompt or corpus must live in the directory whose basename
matches its owning Terraform file, as listed above. Shared assets alone belong
in `tama/graph/corpora/`. Generic cross-handler candidate normalization must not
return under another name.

## Test plan

### Static graph tests

Use native Terraform mock-provider tests to assert:

- the production root and component nodes exist and are enabled only in the
  completed topology;
- the Tooling module/reference and its parameters match this document;
- exactly one thought tool is bound to `memory_post_create`;
- exactly two modifiers have the specified indexes, targets, metadata sources,
  and error policies;
- the model has `parallel_tool_calls: false`, required tool selection, and
  `consecutive_limit: 2`;
- HTTP recovery allows POST and has exactly one configured retry;
- routing covers memo, external action, and invalid/default paths;
- external action routing covers `200`, `201`, `0`, and other-status paths;
- every component terminal forwards to the root result publication request;
- candidate, status, and retry-save stages are absent;
- #12 resolves only `memory_post_create`; it does not bind projection snapshot,
  projection completion, or the future index action;
- the test-only result fixture remains disabled unless explicitly enabled.

### Fixture behavior

Retain the R01-R08 fixture intent from issue #12. Tests must cover at least:

- direct memory extraction from a clear instruction;
- preservation of the user's original content;
- title, metadata, and tag shaping;
- ambiguous input choosing memo clarification with zero writes;
- invalid generated arguments receiving bounded model continuation;
- `201` producing a non-replayed saved receipt;
- `200` producing a replayed saved receipt;
- a timeout-after-commit using the same origin identifier and producing only
  one Post;
- exhausted transport uncertainty producing `failed/save_unconfirmed`;
- malformed, mismatched, and spoofed responses producing
  `failed/invalid_tool_result`;
- missing trusted metadata preventing HTTP execution.

Terraform mock tests prove graph construction, not model quality. Prompt and
corpus fixtures prove deterministic transformations. A live OpenRouter/Tama run
is required to accept provider behavior.

### Application regression

Run focused endpoint/idempotency tests:

```bash
mix test \
  test/memovee_web/controllers/tama/memory/post_controller_test.exs \
  test/memovee/memory/post/manager_test.exs \
  test/memovee/memory/concurrent_save_test.exs
```

Then run the repository gate:

```bash
mix precommit
```

### Terraform gate

```bash
terraform -chdir=tama fmt -check -recursive
terraform -chdir=tama validate
terraform -chdir=tama test
```

Run `terraform plan` only with the intended workspace configuration. Do not
apply as part of static verification.

## Acceptance criteria

Implementation is complete when all of the following are true:

- A clear remember request reaches one Tooling execution and returns a
  schema-valid saved receipt.
- A replay with the same trusted origin returns the same logical Post and sets
  `replayed` correctly.
- A new Post transaction leaves exactly one durable pending indexing record and
  one Oban job; remember does not wait for entity enrichment or index readiness.
- An ambiguous request returns one bounded clarification question and performs
  no external save.
- Actor and origin identifiers come only from trusted metadata modifiers.
- One retryable POST failure causes at most one exact-request retry inside
  Tooling.
- An uncertain transport outcome returns `failed/save_unconfirmed` without
  claiming the write failed or issuing an independent second save.
- Real HTTP failures and invalid tool results terminate as schema-valid failed
  results with sanitized details.
- All terminal results are forwarded to and published by the existing root
  `tama/agentic/result` chain.
- Obsolete candidate/status/retry-save graph resources are removed through a
  reviewed Terraform plan.
- Static Terraform, fixture, focused application, and `mix precommit` gates are
  green.
- Live runtime acceptance passes after authorized apply and Tama restart.

## Operational prerequisites and blockers

The code can be implemented without live credentials. Deployment acceptance
still requires:

- a completed imported memory API specification;
- an active source with valid identity/credentials;
- the `memory_post_create` operation in the configured operation set;
- OpenRouter credentials for live model execution;
- a reviewed Terraform plan and separate apply approval;
- a Tama restart/recreation after graph and queue changes.

Issue #13 is not a blocker. A saved receipt may legitimately report a pending
indexing status until indexing is implemented. Its downstream contract is the
movie-details-style entity pipeline ending at `/tama/memory/index`, not the old
snapshot/completion callback pair.

## Delivery checklist

- [x] Confirm state addresses before editing/removing graph resources.
- [x] Add Tooling prompt, action binding, trusted modifiers, and retry policy.
- [x] Add deterministic saved/clarification/failure routing.
- [x] Forward every component terminal to root result publication.
- [x] Remove candidate/status/retry-save topology.
- [x] Update outputs, graph documentation, and stage inventory tests.
- [x] Pass focused application tests.
- [x] Pass Terraform fmt, validate, and test.
- [x] Pass `mix precommit`.
- [x] Review the Terraform plan, including all destroys/replacements.
- [ ] Obtain approval before apply.
- [ ] Restart Tama and complete live R01-R08 acceptance.

## Source verification

Verified on 2026-09-22 without planning or applying the workspace:

- the focused endpoint, manager, and concurrent-save suite passed 36 tests;
- `mix precommit` passed 344 tests plus compile, format, and strict Credo;
- Terraform format and validation passed, and all 7 mock-provider runs passed;
- the pinned Tama 0.15.0 runtime rendered 13 deterministic corpus fixtures,
  including create, replay, transport ambiguity, retryable HTTP failure,
  clarification, malformed types, mismatched identity, and multiple calls.

The corpus fixtures are now conventional ExUnit tests using the same Solid
version and JSON filter behavior as Tama 0.15.0. They run in `mix precommit`
and CI through the existing `mix test` step.

At that 2026-09-22 checkpoint, the state still owned obsolete candidate,
invalid-candidate, status, and retry-save chains/classes. No plan or live
runtime acceptance was claimed at that point.

On 2026-09-23, the authenticated, read-only `/tama/health` endpoint and
Tama-0.15-compatible `bearer_auth` OpenAPI scheme were added. The identity
binds the two private Agent API token fields into one `api_key`, waits for
validation, and gates the remember tool and entry nodes. `mix precommit`
passed 359 tests; Terraform format, validate, and all 8 mock-plan tests passed.
The running Memovee OpenAPI advertises the new health operation and scheme.
The read-only Terraform plan reports one identity create and one specification
update, with no removals or replacements. No apply, Tama restart, OpenRouter
call, or live R01-R08 trace is claimed.
