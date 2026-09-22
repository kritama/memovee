module "remember-clarification-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-write.id
  title       = "remember-clarification-request"
  description = "Memory v1 remember-clarification handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "remember-clarification" {
  space_id = tama_space.memory-write.id
  name     = "remember-clarification"
}

resource "tama_class_corpus" "remember-clarification-result" {
  class_id = tama_class.remember-tool-result.id
  name     = "Remember clarification result"
  template = file("${path.module}/remember-clarification/remember-clarification-result.liquid")
}

resource "tama_modular_thought" "remember-clarification-tool-result" {
  chain_id        = tama_chain.remember-clarification.id
  index           = 0
  relation        = "tool-result"
  output_class_id = tama_class.remember-tool-result.id

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

resource "tama_thought_module_input" "remember-clarification-tool-result" {
  thought_id      = tama_modular_thought.remember-clarification-tool-result.id
  class_corpus_id = tama_class_corpus.remember-tooling-result.id
  type            = "concept"
}

resource "tama_modular_thought" "remember-clarification-result" {
  chain_id        = tama_chain.remember-clarification.id
  index           = 1
  relation        = "result"
  output_class_id = tama_class.memory-write-result.id

  module {
    reference = "tama/concepts/render"
    parameters = jsonencode({
      relation = "tool-result"
      inputs   = {}
    })
  }

  faculty {
    queue_id = tama_queue.interactive.id
    priority = 0
  }
}

resource "tama_thought_module_input" "remember-clarification-result" {
  thought_id      = tama_modular_thought.remember-clarification-result.id
  class_corpus_id = tama_class_corpus.remember-clarification-result.id
  type            = "concept"
}

resource "tama_thought_initializer" "remember-clarification-result" {
  thought_id = tama_modular_thought.remember-clarification-tool-result.id
  class_id   = module.remember-clarification-request.class.id
  reference  = "tama/initializers/import"

  parameters = jsonencode({
    resources = [{
      type     = "concept"
      property = "forwarded_from_concept_id"
      scope    = "global"
    }]
  })
}

resource "tama_modular_thought" "remember-clarification-forward" {
  chain_id        = tama_chain.remember-clarification.id
  index           = 2
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

resource "tama_thought_path" "remember-clarification-to-root" {
  thought_id      = tama_modular_thought.remember-clarification-forward.id
  target_class_id = module.remember-result-publication-request.class.id
  depends_on      = [tama_space_bridge.memory-write-to-remember]
}

resource "tama_node" "remember-clarification" {
  count    = local.remember_enabled ? 1 : 0
  space_id = tama_space.memory-write.id
  class_id = module.remember-clarification-request.class.id
  chain_id = tama_chain.remember-clarification.id
  type     = "reactive"
  on       = "processing"

  depends_on = [
    tama_thought_initializer.remember-clarification-result,
    tama_thought_module_input.remember-clarification-tool-result,
    tama_thought_module_input.remember-clarification-result,
    tama_thought_path.remember-clarification-to-root
  ]
}
