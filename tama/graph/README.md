# Memory graph

This child module extends the existing `tama/` Terraform root and its global
foundation. Follow the same structure as `upmaru/memovee-tama`: Terraform resources,
JSON schemas, Liquid corpora and Markdown prompts. There is no Python tooling or
separate configuration validator.

From the application root, use the existing Terraform installation:

```sh
terraform -chdir=tama init
terraform -chdir=tama fmt -check -recursive
terraform -chdir=tama validate
terraform -chdir=tama plan
```

`terraform test` runs the optional mock-provider checks without deploying anything.
Applying a reviewed plan requires explicit deployment authorization.

`tama/versions.tf` pins provider 0.7.0 directly. Base 0.5.6 and `module.global`
retain their existing addresses. Use Terraform consistently for the tracked
provider lockfile. Future Tama Kit reruns must preserve this application pin and
reconcile the manifest's original generated-file hash; it has not been rewritten.
The local instance is already bootstrapped; ordinary graph validation and planning
do not rerun bootstrap. Its existing manifest/topology mismatch remains a separate
Tama Kit rerun issue.

## Schemas and consumers

Use lowercase kebab-case names with a version suffix for every JSON schema and
fixture file: `some-schema.v1.json`. Keep assets used by one Terraform file in a
folder with the same basename as that file:

- `memory-write/`: memory candidate provider schema.
- `memory-query/`: query and answer candidate provider schemas.
- `memory-index/`: description provider schema.
- `memory-projection/`: projection request schema.

`schemas/memory-contract.v1.json` is the shared memory data contract published in
issue #9. `schemas.tf` loads it for the result classes in both `remember.tf` and
`recall.tf`. `schemas/memory-fixtures.v1.json` holds the examples from #16 for
future tests; nothing currently consumes it. The v1 bundle retains its gated
v1.1 definitions; renaming files does not change contract versions or payloads.

`corpora/` holds shared assets: `generation-input.md` is used by memory write,
query and index; `json.liquid` is used by both roots. Provider schemas wrap the
domain value for structured model output and are read directly by Terraform.
Backend ownership, payload semantics and idempotency belong in #10's Elixir code
and tests; Terraform configuration validation cannot enforce them.

The graph follows the feature-oriented file layout in `memovee-tama`:

- `remember.tf` and `recall.tf` declare the roots, outgoing bridges, forwarding
  and result delivery foundations.
- `memory-write.tf`, `memory-query.tf` and `memory-index.tf` declare component
  spaces, outgoing bridges and shared generation inputs and output classes.
- `memory-api.tf` and `memory-inference.tf` declare the shared service components;
  `models.tf` and `queues.tf` hold model and worker configuration.
- Files such as `remember-candidate.tf`, `remember-save.tf`, `recall-search.tf`
  and `index-snapshot.tf` keep each handler's request class, chain and node together.
- `outputs.tf` exposes the public interfaces; it does not construct the graph.

#11 adds result delivery and #12/#13/#15 fill the remember/index/recall chains.
Reactive nodes have `count = 0` in their owning files until those chains have real terminal paths.
`memory_interfaces.ready` is therefore false. The API source space and explicit
operation-ID lookup interfaces wait for the real backend specification; #13 owns
the embeddings OpenAPI source. Tama #114–#116 remain runtime prerequisites.

## Local development

Inference uses OpenRouter's `https://openrouter.ai/api/v1/chat/completions`
endpoint with model `z-ai/glm-5.3-flash`, following the existing `memovee-tama`
integration pattern. Record the actual served model/provider in live evaluations.
OpenRouter's [model reference](https://openrouter.ai/z-ai/glm-5.3-flash) lists JSON output support without JSON-schema
enforcement. Generation consumers must validate candidates and apply the bounded
repair/failure behavior before any write; verify the runtime's output-format
compatibility before enabling those chains.
See the [OpenRouter API guide](https://openrouter.ai/docs/quickstart).

Manage local services directly with Docker Compose and Mix. Memovee owns
PostgreSQL and Redis in the root `compose.yaml`:

```sh
docker compose up -d --wait postgres memory-redis
mix ecto.migrate
mix phx.server
```

Stop Phoenix with its terminal, and stop the dependencies without removing data:

```sh
docker compose stop postgres memory-redis
```

Use the existing bootstrapped Compose configuration to manage Tama and Caddy.
The graph does not add lifecycle scripts or a proxy override. Redis uses AOF,
the `memovee-memory-redis-data` volume and host URL
`redis://127.0.0.1:6380/0`; configure the application's Redis connection when
implementing indexing.

Supply the OpenRouter key to Terraform through your local environment:

```sh
export TF_VAR_memory_openrouter_api_key="${OPENROUTER_API_KEY:?Set OPENROUTER_API_KEY}"
terraform -chdir=tama plan -out=memory.tfplan
```

Use the existing Tama provisioner environment for provider authentication.
Service Actor credentials, runtime feature/queue checks and live traces belong
to the integration work that enables the graph consumers.

Static/mock tests are not live acceptance. Service credentials, dependency image,
loaded queues, real provider messages and root-message/result traces still need
integration verification. #16 owns the full memory evaluation suite.

## Memory HTTP persistence

Memovee publishes `memory_post_create` at `POST /tama/memory/posts` in
`/tama/openapi`. Tama retains the original message, extracts the structured Post,
and submits it under `post`, with the runtime-owned `context` alongside it.

```json
{
  "context": {
    "actor_id": "01990000-0000-7000-8000-000000000001",
    "origin_identifier": "mcp-app:message:v1:example"
  },
  "post": {
    "title": "Memovee HTTP client preference",
    "body": "For Memovee, I prefer Req for HTTP calls.",
    "metadata": {
      "kind": "preference",
      "epistemic_status": "user_stated",
      "approval": "unspecified",
      "source": {
        "channel": "agent",
        "reference": null
      },
      "occurred_at": null,
      "effective_at": null,
      "derived_from_post_ids": []
    },
    "tags": [
      {
        "namespace": "tool",
        "key": "req",
        "name": "Req"
      }
    ]
  }
}
```

The save endpoint accepts only the configured Tama service. Context injection remains
at `/body/context/actor_id` and `/body/context/origin_identifier`; generated fields
are nested under `/body/post`.

Set `MEMOVEE_MEMORY_TAMA_ACTOR_ID` to the dedicated service Actor's UUID and supply
that Actor's existing API credential to the graph API source. Agents submit memories
through `remember`; the service supplies `context.actor_id` and
`context.origin_identifier` on their behalf. Ordinary API credentials cannot save directly.

The Post stores the trusted origin identifier. A transaction lock and unique index
on owner/origin ensure concurrent retries create one Post, its tags, search projection
and Oban job. A saved origin returns the existing Post before candidate validation,
so changed extraction wording cannot create another memory. Receipts are built from
the current Post, tags and indexing state; there is no duplicated source or receipt
snapshot. An uncertain save can retry the same POST once with the same trusted context.
If that retry is also inconclusive, report `save_unconfirmed` rather than assuming
nothing was saved.

Ownership is required from the first migration. There is no
ingestion model, pre-extraction registration or status endpoint. #12 owns the graph
save caller, #13 owns indexing execution, and #14 owns search.

Projection scheduling uses [Oban](https://oban.hexdocs.pm/Oban.html). Every new
projection revision inserts an Oban job in the same database transaction. Oban
owns queue execution, attempts, retry scheduling and orphaned-job recovery; there
is no custom dispatcher or lease-renewal loop. `Memovee.Projections.Indexing` keeps
revision/fingerprint, generated artifacts and durable readiness independently of
Oban's job retention. Its existing `lease_token` field is reserved for fencing
future asynchronous graph callbacks, not queue scheduling.

`revision` identifies the Post content revision; `indexing_version` is the integer
indexing method version, initially `1`. Indexing records are unique by
`(post_id, revision, indexing_version)`, and the fingerprint and generation/search
contracts include that version.

The `memory_projection` queue has concurrency four and starts paused until #13
implements execution. Jobs allow five attempts with retry delays of 1, 5, 30 and
120 seconds. Tests use Oban's manual mode. The worker deliberately returns an
error if invoked before the pipeline is implemented, rather than acknowledging
indexing success.
