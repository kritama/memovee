module "remember-invalid-response-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-write.id
  title       = "remember-invalid-response-request"
  description = "Memory v1 remember-invalid-response handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "remember-invalid-response" {
  space_id = tama_space.memory-write.id
  name     = "remember-invalid-response"
}

resource "tama_class_corpus" "remember-invalid-response-result" {
  class_id = var.global_schemas["tool-call"]
  name     = "Remember invalid tool result"
  template = file("${path.module}/remember-invalid-response/remember-invalid-response-result.liquid")
}

resource "tama_modular_thought" "remember-invalid-response-result" {
  chain_id        = tama_chain.remember-invalid-response.id
  index           = 0
  relation        = "result"
  output_class_id = tama_class.memory-write-result.id

  module {
    reference = "tama/concepts/render"
    parameters = jsonencode({
      relation = "remember-tooling"
      inputs   = {}
    })
  }

  faculty {
    queue_id = tama_queue.interactive.id
    priority = 0
  }
}

resource "tama_thought_module_input" "remember-invalid-response-result" {
  thought_id      = tama_modular_thought.remember-invalid-response-result.id
  class_corpus_id = tama_class_corpus.remember-invalid-response-result.id
  type            = "concept"
}

resource "tama_thought_initializer" "remember-invalid-response-result" {
  thought_id = tama_modular_thought.remember-invalid-response-result.id
  class_id   = module.remember-invalid-response-request.class.id
  reference  = "tama/initializers/import"

  parameters = jsonencode({
    resources = [{
      type     = "concept"
      property = "forwarded_from_concept_id"
      scope    = "global"
    }]
  })
}

resource "tama_modular_thought" "remember-invalid-response-forward" {
  chain_id        = tama_chain.remember-invalid-response.id
  index           = 1
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

resource "tama_thought_path" "remember-invalid-response-to-root" {
  thought_id      = tama_modular_thought.remember-invalid-response-forward.id
  target_class_id = module.remember-result-publication-request.class.id
  depends_on      = [tama_space_bridge.memory-write-to-remember]
}

resource "tama_node" "remember-invalid-response" {
  count    = local.remember_enabled ? 1 : 0
  space_id = tama_space.memory-write.id
  class_id = module.remember-invalid-response-request.class.id
  chain_id = tama_chain.remember-invalid-response.id
  type     = "reactive"
  on       = "processing"

  depends_on = [
    tama_thought_initializer.remember-invalid-response-result,
    tama_thought_module_input.remember-invalid-response-result,
    tama_thought_path.remember-invalid-response-to-root
  ]
}
