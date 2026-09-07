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

`schemas/schemas.json` is the memory v1 data contract published in issue #9;
Terraform reads it to define the root result classes. `schemas/fixtures.json`
holds the examples from #16 for future tests; nothing currently consumes it.
JSON schemas in `schemas/` are read directly by Terraform.
The provider schemas wrap the domain value for structured model output.
Backend ownership, payload semantics and idempotency belong in #10's Elixir code
and tests; Terraform configuration validation cannot enforce them.

The graph follows the feature-oriented file layout in `memovee-tama`:

- `remember.tf` and `recall.tf` declare the roots, outgoing bridges, forwarding
  and result delivery foundations.
- `memory-write.tf`, `memory-query.tf` and `memory-index.tf` declare component
  spaces, outgoing bridges and shared generation inputs and output classes.
- `memory-api.tf` and `memory-inference.tf` declare the shared service components;
  `models.tf` and `queues.tf` hold model and worker configuration.
- Files such as `remember-ingestion.tf`, `remember-save.tf`, `recall-search.tf`
  and `index-snapshot.tf` keep each handler's request class, chain and node together.
- `outputs.tf` exposes the public interfaces; it does not construct the graph.

#11 adds result delivery and #12/#13/#15 fill the ingestion/index/recall chains.
Reactive nodes have `count = 0` in their owning files until those chains have real terminal paths.
`memory_interfaces.ready` is therefore false. The API source space and explicit
operation-ID lookup interfaces wait for the real backend specification; #13 owns
the embeddings OpenAPI source. Tama #114–#116 remain runtime prerequisites.

## Local development

Inference uses OpenRouter's `https://openrouter.ai/api/v1/chat/completions`
endpoint with model `openai/gpt-4.1-mini`, following the existing `memovee-tama`
integration. This is OpenRouter's model identifier, not the previous dated
OpenAI snapshot pin. Record the actual served model/provider in live evaluations.
See the [OpenRouter API guide](https://openrouter.ai/docs/quickstart).

`scripts/memory-dev {start|stop|check|plan} [--dry-run]` is a shell wrapper for
Docker Compose, Mix and Terraform. It uses Bash, jq and standard Linux utilities.
`check` probes runtime readiness; it does not replace Terraform validation.

Store `MEMOVEE_MEMORY_TAMA_ACTOR_ID`, `MEMOVEE_MEMORY_TAMA_API_CREDENTIAL` and
`OPENROUTER_API_KEY` in ignored `tama/.memory.env`, mode 0600. The existing provisioner
credentials stay in `tama/.tama.env`; the provider environment path comes from the
Tama Kit manifest. Source these local files only from a trusted checkout.
For direct Terraform use, set `TF_VAR_memory_openrouter_api_key` from the OpenRouter key
without printing it; the `plan` wrapper does this automatically.

Memovee owns Redis alongside PostgreSQL in the root `compose.yaml`. Start it with
`docker compose up -d memory-redis`; no extra Compose file or profile is required.
Redis 8.2.1 uses AOF, a named volume and loopback port 6380. Its development
URL default applies only to this runner; production requires explicit configuration.
The runner reuses the existing Compose project and Tama database. Phoenix runs
on the host in development mode at port 4000; Tama remains a production release.
`compose.host.yaml` only overrides Caddy routing for this host-run Phoenix setup.
An already-running Caddy must be stopped explicitly before changing its routing
from containerized Memovee to this host profile.

The runner starts services explicitly with `--no-deps --no-recreate`, records the
container IDs and Phoenix PID/start identity it owns, and stops only those.
Volumes are retained. Failed startup retains the ownership files for `stop`.
Private logs, ownership files and saved plans live in ignored `tama/.memory/`.
The `plan` command saves `.memory/memory.tfplan`; inspect it locally with Terraform
before an authorized apply. Neither `start` nor `plan` applies graph changes.

Static/mock tests are not live acceptance. Service credentials, dependency image,
loaded queues, real provider messages and root-message/result traces still need
integration verification. #16 owns the full memory evaluation suite.
