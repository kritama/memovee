module "remember" {
  source  = "upmaru/base/tama//modules/messaging"
  version = "0.5.6"
  name    = "remember"
}

resource "tama_space_bridge" "remember-to-memory-write" {
  space_id        = module.remember.space_id
  target_space_id = tama_space.memory-write.id
}

module "remember-result-publication-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = module.remember.space_id
  title       = "memory-result-request"
  description = "Return a validated result only to the originating remember root."
}

resource "tama_class" "remember-result" {
  space_id = module.remember.space_id
  schema_json = jsonencode(merge(local.contracts, {
    title       = "remember-result"
    description = "Root publication for remember; runtime owns transport correlation fields."
    "$ref"      = "#/$defs/ResultPublication"
  }))
}

resource "tama_chain" "remember-result-delivery" {
  space_id = module.remember.space_id
  name     = "remember-result"
}

# #11 enables result delivery only after the terminal path is implemented.
resource "tama_node" "remember-result-delivery" {
  count    = 0
  space_id = module.remember.space_id
  class_id = module.remember-result-publication-request.class.id
  chain_id = tama_chain.remember-result-delivery.id
  type     = "reactive"
  on       = "processing"
}

resource "tama_chain" "remember-forward" {
  space_id = module.remember.space_id
  name     = "remember-forward"
}

resource "tama_modular_thought" "remember-forward" {
  chain_id        = tama_chain.remember-forward.id
  relation        = "forwarding"
  index           = 0
  output_class_id = var.global_schemas["forwarding"]
  module { reference = "tama/concepts/forward" }
  faculty {
    queue_id = tama_queue.interactive.id
    priority = 0
  }
}

resource "tama_class_corpus" "remember-message" {
  class_id = module.remember.schemas["user-message"].id
  name     = "Exact message JSON"
  template = file("${path.module}/corpora/json.liquid")
}

resource "tama_thought_module_input" "remember-forward" {
  thought_id      = tama_modular_thought.remember-forward.id
  class_corpus_id = tama_class_corpus.remember-message.id
  type            = "entity"
}

resource "tama_thought_path" "remember-forward" {
  thought_id      = tama_modular_thought.remember-forward.id
  target_class_id = module.memory-write-request.class.id
  depends_on      = [tama_space_bridge.remember-to-memory-write]
}

# Enable only when the component chain and root result path are complete.
resource "tama_node" "remember-forward" {
  count    = 0
  space_id = module.remember.space_id
  class_id = module.remember.schemas["user-message"].id
  chain_id = tama_chain.remember-forward.id
  type     = "reactive"
  on       = "processing"
}
