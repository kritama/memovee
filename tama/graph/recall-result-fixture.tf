# Deterministic, test-gated path used to prove result publication before #15
# supplies real query/search/answer outcomes. Production keeps the entry nodes absent.
resource "tama_class_corpus" "recall-result-fixture-message" {
  class_id = module.recall.schemas["user-message"].id
  name     = "Recall result fixture"
  template = file("${path.module}/corpora/recall-result-fixture.liquid")
}

resource "tama_chain" "recall-result-fixture-root" {
  space_id = module.recall.space_id
  name     = "recall-result-fixture-root"
}

resource "tama_modular_thought" "recall-result-fixture-render" {
  chain_id        = tama_chain.recall-result-fixture-root.id
  relation        = "result-fixture"
  index           = 0
  output_class_id = tama_class.recall-result.id

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

resource "tama_thought_module_input" "recall-result-fixture-render" {
  thought_id      = tama_modular_thought.recall-result-fixture-render.id
  class_corpus_id = tama_class_corpus.recall-result-fixture-message.id
  type            = "entity"
}

resource "tama_modular_thought" "recall-result-fixture-forward" {
  chain_id        = tama_chain.recall-result-fixture-root.id
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

resource "tama_thought_path" "recall-result-fixture-to-memory-query" {
  thought_id      = tama_modular_thought.recall-result-fixture-forward.id
  target_class_id = module.memory-query-request.class.id
  depends_on      = [tama_space_bridge.recall-to-memory-query]
}

resource "tama_node" "recall-result-fixture-root" {
  count    = var.enable_result_fixtures ? 1 : 0
  space_id = module.recall.space_id
  class_id = module.recall.schemas["user-message"].id
  chain_id = tama_chain.recall-result-fixture-root.id
  type     = "reactive"
  on       = "processing"

  depends_on = [
    tama_thought_module_input.recall-result-fixture-render,
    tama_thought_path.recall-result-fixture-to-memory-query
  ]
}

resource "tama_class_corpus" "recall-result-fixture-publication" {
  class_id = tama_class.recall-result.id
  name     = "Recall result publication"
  template = file("${path.module}/corpora/recall-result-fixture-publication.liquid")
}

resource "tama_chain" "recall-result-fixture-component" {
  space_id = tama_space.memory-query.id
  name     = "recall-result-fixture-component"
}

resource "tama_modular_thought" "recall-result-fixture-component-render" {
  chain_id        = tama_chain.recall-result-fixture-component.id
  relation        = "result"
  index           = 0
  output_class_id = tama_class.memory-query-result.id

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

resource "tama_thought_module_input" "recall-result-fixture-component-render" {
  thought_id      = tama_modular_thought.recall-result-fixture-component-render.id
  class_corpus_id = tama_class_corpus.recall-result-fixture-publication.id
  type            = "concept"
}

resource "tama_thought_initializer" "recall-result-fixture-component-import" {
  thought_id = tama_modular_thought.recall-result-fixture-component-render.id
  class_id   = module.memory-query-request.class.id
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

resource "tama_modular_thought" "recall-result-fixture-component-forward" {
  chain_id        = tama_chain.recall-result-fixture-component.id
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

resource "tama_thought_path" "recall-result-fixture-to-root" {
  thought_id      = tama_modular_thought.recall-result-fixture-component-forward.id
  target_class_id = module.recall-result-publication-request.class.id
  depends_on      = [tama_space_bridge.memory-query-to-recall]
}

resource "tama_node" "recall-result-fixture-component" {
  count    = var.enable_result_fixtures ? 1 : 0
  space_id = tama_space.memory-query.id
  class_id = module.memory-query-request.class.id
  chain_id = tama_chain.recall-result-fixture-component.id
  type     = "reactive"
  on       = "processing"

  depends_on = [
    tama_thought_initializer.recall-result-fixture-component-import,
    tama_thought_module_input.recall-result-fixture-component-render,
    tama_thought_path.recall-result-fixture-to-root
  ]
}
