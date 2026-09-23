module "remember-receipt-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-write.id
  title       = "remember-receipt-request"
  description = "Memory v1 remember-receipt handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "remember-receipt" {
  space_id = tama_space.memory-write.id
  name     = "remember-receipt"
}

resource "tama_modular_thought" "remember-receipt-forward" {
  chain_id        = tama_chain.remember-receipt.id
  index           = 0
  relation        = "result-forwarding"
  output_class_id = var.global_schemas["forwarding"]

  module {
    reference = "tama/concepts/forward"
    parameters = jsonencode({
      relation = "result"
    })
  }

  faculty {
    queue_id = tama_queue.interactive.id
    priority = 0
  }
}

resource "tama_thought_initializer" "remember-receipt-forward" {
  thought_id = tama_modular_thought.remember-receipt-forward.id
  class_id   = module.remember-receipt-request.class.id
  reference  = "tama/initializers/import"

  parameters = jsonencode({
    resources = [{
      type     = "concept"
      property = "forwarded_from_concept_id"
      scope    = "global"
    }]
  })
}

resource "tama_thought_path" "remember-receipt-to-root" {
  thought_id      = tama_modular_thought.remember-receipt-forward.id
  target_class_id = module.remember-result-publication-request.class.id
  depends_on      = [tama_space_bridge.memory-write-to-remember]
}

resource "tama_node" "remember-receipt" {
  count    = local.remember_enabled ? 1 : 0
  space_id = tama_space.memory-write.id
  class_id = module.remember-receipt-request.class.id
  chain_id = tama_chain.remember-receipt.id
  type     = "reactive"
  on       = "processing"

  depends_on = [
    tama_thought_initializer.remember-receipt-forward,
    tama_thought_path.remember-receipt-to-root
  ]
}
