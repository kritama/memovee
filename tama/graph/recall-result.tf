# Handler foundation; issue #15 supplies the executable chain.

module "recall-result-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-query.id
  title       = "recall-result-request"
  description = "Memory v1 recall-result handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "recall-result" {
  space_id = tama_space.memory-query.id
  name     = "recall-result"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "recall-result" {
  count    = 0
  space_id = tama_space.memory-query.id
  class_id = module.recall-result-request.class.id
  chain_id = tama_chain.recall-result.id
  type     = "reactive"
  on       = "processing"
}
