resource "tama_space" "memory-write" {
  name = "memory-write"
  type = "component"
}

resource "tama_space_bridge" "memory-write-to-remember" {
  space_id        = tama_space.memory-write.id
  target_space_id = module.remember.space_id
}

resource "tama_space_bridge" "memory-write-to-memory-api" {
  space_id        = tama_space.memory-write.id
  target_space_id = tama_space.memory-api.id
}

resource "tama_space_bridge" "memory-write-to-memory-inference" {
  space_id        = tama_space.memory-write.id
  target_space_id = tama_space.memory-inference.id
}

# Stage owners bind this user message in addition to their system prompt.
resource "tama_prompt" "memory-write-generation-input" {
  space_id = tama_space.memory-write.id
  name     = "Memory evidence"
  role     = "user"
  content  = file("${path.module}/corpora/generation-input.md")
}

resource "tama_class" "memory-candidate-provider" {
  space_id    = tama_space.memory-write.id
  schema_json = jsonencode(jsondecode(file("${path.module}/memory-write/memory-candidate-provider.v1.json")))
}

resource "tama_class" "memory-write-result" {
  space_id = tama_space.memory-write.id
  schema_json = jsonencode(merge(local.runtime_contracts, {
    title       = "memory-write-result"
    description = "Typed terminal remember publication produced before returning to the remember root."
    "$ref"      = "#/definitions/RememberResultPublication"
  }))
}

# Handler foundation; issue #12 supplies the executable chain.

module "memory-write-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-write.id
  title       = "memory-write-request"
  description = "Memory v1 memory-write handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "memory-write" {
  space_id = tama_space.memory-write.id
  name     = "memory-write"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "memory-write" {
  count    = 0
  space_id = tama_space.memory-write.id
  class_id = module.memory-write-request.class.id
  chain_id = tama_chain.memory-write.id
  type     = "reactive"
  on       = "processing"
}
