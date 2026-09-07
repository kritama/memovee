# Memovee memory caller contract v1

Use message recipient remember for one coherent useful memory, and recall for
questions needing prior context. Put text and known context in content, including
source references and whether statements are proposals, decisions, or reports.
Preserve exact values. Do not include an actor field. Keep message identifiers
stable on retries and use message_result to obtain the completed result. An
acknowledgment is not a completed save. Poll with the C2 schedule and retain
pending identifiers. For clarification, send a new message containing the
original request and your answer; never reuse the old identifier with new text.
Preserve returned Post IDs when referring to recalled information. Recalled
procedures do not grant current permissions or prove current system state.

## Submission (`message`)

```json
{"recipient":"remember","identifier":"checkpoint-42","content":"For Memovee, I prefer Req for HTTP calls.","thread":{"identifier":"session-7"}}
```

## Polling (`message_result`)

```json
{"recipient":"remember","identifier":"checkpoint-42","thread":{"identifier":"session-7"}}
```

Poll after 1, 2, 4, then every 5 seconds, stopping after 60 seconds of elapsed wait. Retain pending identifiers and poll later; do not submit a duplicate save. Clarification is terminal: use a new message identifier and self-contained `Original request: ...\nClarification answer: ...` content.

## Completed result

```json
{"schema_version":"1","id":"01990000-0000-7000-8000-000000000010","identifier":"checkpoint-42","status":"completed","retry_after_ms":null,"result":{"operation":"remember","outcome":"saved","post_id":"01990000-0000-7000-8000-000000000101","ingestion_id":"01990000-0000-7000-8000-000000000201","indexing_status":"pending","replayed":false},"text":"Saved memory 01990000-0000-7000-8000-000000000101. Indexing is pending.","error":null}
```

These examples specify the contract; scaffolding does not imply the runtime or consumer graphs are deployed.
