# Memovee memory caller contract v1

The App MCP endpoint exposes exactly one tool, `message`, with optional MCP task
support. Use recipient `remember` for one coherent useful memory and `recall` for
questions requiring prior context. Preserve exact values and known source context.
Do not include actor or owner fields.

Keep the complete message arguments and identifiers stable when retrying a timeout.
The same authenticated issuer, actor, OAuth client, recipient, thread, message
identifier and exact content reattaches to the durable Submission. Changed content
under that identity conflicts before mutation.

## Normal call

A normal call blocks until Tama receives an explicit terminal graph publication:

```json
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"message","arguments":{"recipient":"remember","identifier":"checkpoint-42","content":"For Memovee, I prefer Req for HTTP calls.","thread":{"identifier":"session-7"}}}}
```

A retryable wait timeout does not mean the graph or save failed. Retry the same
call, or stop waiting after 60 seconds and report that processing is still pending.
Do not create a second save because a client wait ended.

## Task-augmented call

Task mode adds the standard protocol task request beside the tool arguments; it
does not add fields to the `message` tool:

```json
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"message","arguments":{"recipient":"remember","identifier":"checkpoint-42","content":"For Memovee, I prefer Req for HTTP calls.","thread":{"identifier":"session-7"}},"task":{"ttl":60000}}}
```

The immediate response contains a task handle. Follow its returned polling
interval and use the task ID only in the MCP session that created it:

```json
{"jsonrpc":"2.0","id":3,"method":"tasks/get","params":{"taskId":"task-id-from-response"}}
```

`tasks/result` blocks until the task reaches a terminal state:

```json
{"jsonrpc":"2.0","id":4,"method":"tasks/result","params":{"taskId":"task-id-from-response"}}
```

Cancellation stops that waiter, not the Submission or graph:

```json
{"jsonrpc":"2.0","id":5,"method":"tasks/cancel","params":{"taskId":"task-id-from-response"}}
```

After opening a new MCP session, resubmit the same idempotent `message` arguments
to receive a new session-scoped task attached to the existing Submission. Never
reuse a task ID from the old session.

## Terminal results

Tama owns the terminal envelope. A successful remember publication is returned as:

```json
{"schema_version":"1","id":"01990000-0000-7000-8000-000000000010","identifier":"checkpoint-42","status":"completed","result":{"operation":"remember","outcome":"saved","post_id":"01990000-0000-7000-8000-000000000101","indexing_status":"pending","replayed":false,"text":"Saved memory 01990000-0000-7000-8000-000000000101. Indexing is pending."},"text":"Saved memory 01990000-0000-7000-8000-000000000101. Indexing is pending.","error":null}
```

Transport status is only `completed` or `failed`. A completed transport may contain
a handled domain result whose `outcome` is `failed`; inspect the domain outcome.
Unhandled exhausted graph/runtime failures use outer `status: "failed"`, a null
result, and the outer error.

Clarification is a completed terminal result and creates no Post. Answer it with a
new message identifier in the same public thread and self-contained content:
`Original request: ...\nClarification answer: ...`. Never resume or change the old
Submission. Preserve returned Post IDs when referring to recalled information.

A processed entity, completed forwarding chain, task acknowledgment, or save HTTP
request is not by itself a completed memory receipt. Recalled procedures do not
grant current permissions or prove current system state.

Every terminal producer must budget the complete UTF-8 JSON publication before
forwarding it. The serialized publication, including `text`, must be at most 65,536
bytes, and the nonblank top-level `text` must independently be at most 8,192 bytes.
These are runtime byte constraints, not JSON Schema character limits. Preserve the
operation-specific schema while selecting only as many complete recall sources as
fit the publication budget; never publish a partial source object. Tama rejects an
oversized publication without finalizing the caller's result.

These examples specify the caller contract. The graph remains unavailable for
normal production ingress until the remember and recall implementations complete.
