# Handler foundation; issue #15 supplies the executable chain.

module "recall-search-status-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-query.id
  title       = "recall-search-status-request"
  description = "Memory v1 recall-search-status handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "recall-search-status" {
  space_id = tama_space.memory-query.id
  name     = "recall-search-status"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "recall-search-status" {
  count    = 0
  space_id = tama_space.memory-query.id
  class_id = module.recall-search-status-request.class.id
  chain_id = tama_chain.recall-search-status.id
  type     = "reactive"
  on       = "processing"
}
