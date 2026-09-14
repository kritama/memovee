# Deterministic, test-gated path used to prove result publication before #12
# supplies real Tooling/save outcomes. Production keeps the entry nodes absent.
resource "tama_class_corpus" "remember-result-fixture-message" {
  class_id = module.remember.schemas["user-message"].id
  name     = "Remember result fixture"
  template = file("${path.module}/corpora/remember-result-fixture.liquid")
}

resource "tama_chain" "remember-result-fixture-root" {
  space_id = module.remember.space_id
  name     = "remember-result-fixture-root"
}

resource "tama_modular_thought" "remember-result-fixture-render" {
  chain_id        = tama_chain.remember-result-fixture-root.id
  relation        = "result-fixture"
  index           = 0
  output_class_id = tama_class.remember-result.id

  module {
    reference = "tama/concepts/render"
    parameters = jsonencode({
      inputs = {}
    })
  }

  faculty {
    queue_id = tama_queue.interactive.id
    priority = 0
  }
}

resource "tama_thought_module_input" "remember-result-fixture-render" {
  thought_id      = tama_modular_thought.remember-result-fixture-render.id
  class_corpus_id = tama_class_corpus.remember-result-fixture-message.id
  type            = "entity"
}

resource "tama_modular_thought" "remember-result-fixture-forward" {
  chain_id        = tama_chain.remember-result-fixture-root.id
  relation        = "fixture-forwarding"
  index           = 1
  output_class_id = var.global_schemas["forwarding"]

  module {
    reference = "tama/concepts/forward"
    parameters = jsonencode({
      relation = "result-fixture"
    })
  }

  faculty {
    queue_id = tama_queue.interactive.id
    priority = 0
  }
}

resource "tama_thought_path" "remember-result-fixture-to-memory-write" {
  thought_id      = tama_modular_thought.remember-result-fixture-forward.id
  target_class_id = module.memory-write-request.class.id
  depends_on      = [tama_space_bridge.remember-to-memory-write]
}

resource "tama_node" "remember-result-fixture-root" {
  count    = var.enable_result_fixtures ? 1 : 0
  space_id = module.remember.space_id
  class_id = module.remember.schemas["user-message"].id
  chain_id = tama_chain.remember-result-fixture-root.id
  type     = "reactive"
  on       = "processing"

  depends_on = [
    tama_thought_module_input.remember-result-fixture-render,
    tama_thought_path.remember-result-fixture-to-memory-write
  ]
}

resource "tama_class_corpus" "remember-result-fixture-publication" {
  class_id = tama_class.remember-result.id
  name     = "Remember result publication"
  template = file("${path.module}/corpora/remember-result-fixture-publication.liquid")
}

resource "tama_chain" "remember-result-fixture-component" {
  space_id = tama_space.memory-write.id
  name     = "remember-result-fixture-component"
}

resource "tama_modular_thought" "remember-result-fixture-component-render" {
  chain_id        = tama_chain.remember-result-fixture-component.id
  relation        = "result"
  index           = 0
  output_class_id = tama_class.memory-write-result.id

  module {
    reference = "tama/concepts/render"
    parameters = jsonencode({
      relation = "result-fixture"
      inputs   = {}
    })
  }

  faculty {
    queue_id = tama_queue.interactive.id
    priority = 0
  }
}

resource "tama_thought_module_input" "remember-result-fixture-component-render" {
  thought_id      = tama_modular_thought.remember-result-fixture-component-render.id
  class_corpus_id = tama_class_corpus.remember-result-fixture-publication.id
  type            = "concept"
}

resource "tama_thought_initializer" "remember-result-fixture-component-import" {
  thought_id = tama_modular_thought.remember-result-fixture-component-render.id
  class_id   = module.memory-write-request.class.id
  reference  = "tama/initializers/import"

  parameters = jsonencode({
    resources = [
      {
        type     = "concept"
        property = "forwarded_from_concept_id"
        scope    = "global"
      }
    ]
  })
}

resource "tama_modular_thought" "remember-result-fixture-component-forward" {
  chain_id        = tama_chain.remember-result-fixture-component.id
  relation        = "result-forwarding"
  index           = 1
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

resource "tama_thought_path" "remember-result-fixture-to-root" {
  thought_id      = tama_modular_thought.remember-result-fixture-component-forward.id
  target_class_id = module.remember-result-publication-request.class.id
  depends_on      = [tama_space_bridge.memory-write-to-remember]
}

resource "tama_node" "remember-result-fixture-component" {
  count    = var.enable_result_fixtures ? 1 : 0
  space_id = tama_space.memory-write.id
  class_id = module.memory-write-request.class.id
  chain_id = tama_chain.remember-result-fixture-component.id
  type     = "reactive"
  on       = "processing"

  depends_on = [
    tama_thought_initializer.remember-result-fixture-component-import,
    tama_thought_module_input.remember-result-fixture-component-render,
    tama_thought_path.remember-result-fixture-to-root
  ]
}
