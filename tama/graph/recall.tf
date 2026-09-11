module "recall" {
  source  = "upmaru/base/tama//modules/messaging"
  version = "0.5.6"
  name    = "recall"
}

resource "tama_space_bridge" "recall-to-memory-query" {
  space_id        = module.recall.space_id
  target_space_id = tama_space.memory-query.id
}

module "recall-result-publication-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = module.recall.space_id
  title       = "memory-result-request"
  description = "Return a validated result only to the originating recall root."
}

resource "tama_class" "recall-result" {
  space_id = module.recall.space_id
  schema_json = jsonencode(merge(local.runtime_contracts, {
    title       = "recall-result"
    description = "Root publication for recall; runtime owns transport correlation fields."
    "$ref"      = "#/definitions/RecallResultPublication"
  }))
}

resource "tama_chain" "recall-result-delivery" {
  space_id = module.recall.space_id
  name     = "recall-result"
}

resource "tama_modular_thought" "recall-result-delivery" {
  chain_id        = tama_chain.recall-result-delivery.id
  relation        = "result-publication"
  index           = 0
  output_class_id = tama_class.recall-result.id

  module {
    reference  = "tama/agentic/result"
    parameters = jsonencode({})
  }

  faculty {
    queue_id = tama_queue.interactive.id
    priority = 0
  }
}

resource "tama_node" "recall-result-delivery" {
  space_id = module.recall.space_id
  class_id = module.recall-result-publication-request.class.id
  chain_id = tama_chain.recall-result-delivery.id
  type     = "reactive"
  on       = "processing"

  depends_on = [tama_modular_thought.recall-result-delivery]
}

resource "tama_chain" "recall-forward" {
  space_id = module.recall.space_id
  name     = "recall-forward"
}

resource "tama_modular_thought" "recall-forward" {
  chain_id        = tama_chain.recall-forward.id
  relation        = "forwarding"
  index           = 0
  output_class_id = var.global_schemas["forwarding"]
  module { reference = "tama/concepts/forward" }
  faculty {
    queue_id = tama_queue.interactive.id
    priority = 0
  }
}

resource "tama_class_corpus" "recall-message" {
  class_id = module.recall.schemas["user-message"].id
  name     = "Exact message JSON"
  template = file("${path.module}/corpora/json.liquid")
}

resource "tama_thought_module_input" "recall-forward" {
  thought_id      = tama_modular_thought.recall-forward.id
  class_corpus_id = tama_class_corpus.recall-message.id
  type            = "entity"
}

resource "tama_thought_path" "recall-forward" {
  thought_id      = tama_modular_thought.recall-forward.id
  target_class_id = module.memory-query-request.class.id
  depends_on      = [tama_space_bridge.recall-to-memory-query]
}

# Enable only when the component chain and root result path are complete.
resource "tama_node" "recall-forward" {
  count    = 0
  space_id = module.recall.space_id
  class_id = module.recall.schemas["user-message"].id
  chain_id = tama_chain.recall-forward.id
  type     = "reactive"
  on       = "processing"
}
