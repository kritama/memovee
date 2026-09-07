resource "tama_space" "memory-query" {
  name = "memory-query"
  type = "component"
}

resource "tama_space_bridge" "memory-query-to-recall" {
  space_id        = tama_space.memory-query.id
  target_space_id = module.recall.space_id
}

resource "tama_space_bridge" "memory-query-to-memory-api" {
  space_id        = tama_space.memory-query.id
  target_space_id = tama_space.memory-api.id
}

resource "tama_space_bridge" "memory-query-to-memory-inference" {
  space_id        = tama_space.memory-query.id
  target_space_id = tama_space.memory-inference.id
}

# Stage owners bind this user message in addition to their system prompt.
resource "tama_prompt" "memory-query-generation-input" {
  space_id = tama_space.memory-query.id
  name     = "Memory evidence"
  role     = "user"
  content  = file("${path.module}/corpora/generation-input.md")
}

resource "tama_class" "query-candidate-provider" {
  space_id    = tama_space.memory-query.id
  schema_json = jsonencode(jsondecode(file("${path.module}/schemas/query-candidate-provider.json")))
}

resource "tama_class" "answer-candidate-provider" {
  space_id    = tama_space.memory-query.id
  schema_json = jsonencode(jsondecode(file("${path.module}/schemas/answer-candidate-provider.json")))
}

# Handler foundation; issue #15 supplies the executable chain.

module "memory-query-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-query.id
  title       = "memory-query-request"
  description = "Memory v1 memory-query handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "memory-query" {
  space_id = tama_space.memory-query.id
  name     = "memory-query"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "memory-query" {
  count    = 0
  space_id = tama_space.memory-query.id
  class_id = module.memory-query-request.class.id
  chain_id = tama_chain.memory-query.id
  type     = "reactive"
  on       = "processing"
}
