module "remember-save-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-write.id
  title       = "remember-save-request"
  description = "Memory v1 remember-save handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "remember-save" {
  space_id = tama_space.memory-write.id
  name     = "remember-save"
}

resource "tama_class_corpus" "remember-save-result" {
  class_id = tama_class.remember-tool-result.id
  name     = "Remember save result"
  template = file("${path.module}/remember-save/remember-save-result.liquid")
}

resource "tama_modular_thought" "remember-save-tool-result" {
  chain_id        = tama_chain.remember-save.id
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

resource "tama_thought_module_input" "remember-save-tool-result" {
  thought_id      = tama_modular_thought.remember-save-tool-result.id
  class_corpus_id = tama_class_corpus.remember-tooling-result.id
  type            = "concept"
}

resource "tama_modular_thought" "remember-save-result" {
  chain_id        = tama_chain.remember-save.id
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

resource "tama_thought_module_input" "remember-save-result" {
  thought_id      = tama_modular_thought.remember-save-result.id
  class_corpus_id = tama_class_corpus.remember-save-result.id
  type            = "concept"
}

resource "tama_thought_initializer" "remember-save-result" {
  thought_id = tama_modular_thought.remember-save-tool-result.id
  class_id   = module.remember-save-request.class.id
  reference  = "tama/initializers/import"

  parameters = jsonencode({
    resources = [{
      type     = "concept"
      property = "forwarded_from_concept_id"
      scope    = "global"
    }]
  })
}

resource "tama_class_corpus" "remember-result-json" {
  class_id = tama_class.memory-write-result.id
  name     = "Remember result JSON"
  template = file("${path.module}/corpora/json.liquid")
}

resource "tama_modular_thought" "remember-save-route" {
  chain_id        = tama_chain.remember-save.id
  index           = 2
  relation        = "result-route"
  output_class_id = var.global_schemas["forwarding"]

  module {
    reference = "tama/concepts/dispatch"
    parameters = jsonencode({
      module = {
        relation        = "result"
        pointer         = "/error/code"
        input_selection = "unique"
      }
    })
  }

  faculty {
    queue_id = tama_queue.interactive.id
    priority = 0
  }
}

resource "tama_thought_module_input" "remember-save-route" {
  thought_id      = tama_modular_thought.remember-save-route.id
  class_corpus_id = tama_class_corpus.remember-result-json.id
  type            = "concept"
}

resource "tama_thought_path" "remember-save-route-receipt" {
  thought_id      = tama_modular_thought.remember-save-route.id
  target_class_id = module.remember-receipt-request.class.id
  parameters = jsonencode({
    path = {
      values  = []
      default = true
    }
  })
}

resource "tama_thought_path" "remember-save-route-unconfirmed" {
  thought_id      = tama_modular_thought.remember-save-route.id
  target_class_id = module.remember-save-unconfirmed-request.class.id
  parameters = jsonencode({
    path = {
      values  = ["save_unconfirmed"]
      default = false
    }
  })
}

resource "tama_thought_path" "remember-save-route-failure" {
  thought_id      = tama_modular_thought.remember-save-route.id
  target_class_id = module.remember-failure-request.class.id
  parameters = jsonencode({
    path = {
      values  = ["save_rejected", "save_unavailable"]
      default = false
    }
  })
}

resource "tama_thought_path" "remember-save-route-invalid" {
  thought_id      = tama_modular_thought.remember-save-route.id
  target_class_id = module.remember-result-publication-request.class.id
  parameters = jsonencode({
    path = {
      values  = ["invalid_tool_result"]
      default = false
    }
  })

  depends_on = [tama_space_bridge.memory-write-to-remember]
}

resource "tama_node" "remember-save" {
  count    = local.remember_enabled ? 1 : 0
  space_id = tama_space.memory-write.id
  class_id = module.remember-save-request.class.id
  chain_id = tama_chain.remember-save.id
  type     = "reactive"
  on       = "processing"

  depends_on = [
    tama_thought_initializer.remember-save-result,
    tama_thought_module_input.remember-save-tool-result,
    tama_thought_module_input.remember-save-result,
    tama_thought_module_input.remember-save-route,
    tama_thought_path.remember-save-route-receipt,
    tama_thought_path.remember-save-route-unconfirmed,
    tama_thought_path.remember-save-route-failure,
    tama_thought_path.remember-save-route-invalid
  ]
}
