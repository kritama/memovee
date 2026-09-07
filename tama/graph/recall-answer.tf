# Handler foundation; issue #15 supplies the executable chain.

module "recall-answer-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-query.id
  title       = "recall-answer-request"
  description = "Memory v1 recall-answer handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "recall-answer" {
  space_id = tama_space.memory-query.id
  name     = "recall-answer"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "recall-answer" {
  count    = 0
  space_id = tama_space.memory-query.id
  class_id = module.recall-answer-request.class.id
  chain_id = tama_chain.recall-answer.id
  type     = "reactive"
  on       = "processing"
}
