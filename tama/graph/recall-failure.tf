# Handler foundation; issue #15 supplies the executable chain.

module "recall-failure-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-query.id
  title       = "recall-failure-request"
  description = "Memory v1 recall-failure handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "recall-failure" {
  space_id = tama_space.memory-query.id
  name     = "recall-failure"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "recall-failure" {
  count    = 0
  space_id = tama_space.memory-query.id
  class_id = module.recall-failure-request.class.id
  chain_id = tama_chain.recall-failure.id
  type     = "reactive"
  on       = "processing"
}
