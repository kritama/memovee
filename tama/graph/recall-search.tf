# Handler foundation; issue #15 supplies the executable chain.

module "recall-search-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-query.id
  title       = "recall-search-request"
  description = "Memory v1 recall-search handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "recall-search" {
  space_id = tama_space.memory-query.id
  name     = "recall-search"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "recall-search" {
  count    = 0
  space_id = tama_space.memory-query.id
  class_id = module.recall-search-request.class.id
  chain_id = tama_chain.recall-search.id
  type     = "reactive"
  on       = "processing"
}
