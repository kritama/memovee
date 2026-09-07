# Handler foundation; issue #13 supplies the executable chain.

module "index-failure-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-index.id
  title       = "index-failure-request"
  description = "Memory v1 index-failure handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "index-failure" {
  space_id = tama_space.memory-index.id
  name     = "index-failure"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "index-failure" {
  count    = 0
  space_id = tama_space.memory-index.id
  class_id = module.index-failure-request.class.id
  chain_id = tama_chain.index-failure.id
  type     = "reactive"
  on       = "processing"
}
