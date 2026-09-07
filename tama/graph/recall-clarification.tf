# Handler foundation; issue #15 supplies the executable chain.

module "recall-clarification-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-query.id
  title       = "recall-clarification-request"
  description = "Memory v1 recall-clarification handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "recall-clarification" {
  space_id = tama_space.memory-query.id
  name     = "recall-clarification"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "recall-clarification" {
  count    = 0
  space_id = tama_space.memory-query.id
  class_id = module.recall-clarification-request.class.id
  chain_id = tama_chain.recall-clarification.id
  type     = "reactive"
  on       = "processing"
}
