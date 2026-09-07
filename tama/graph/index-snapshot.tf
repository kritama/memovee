# Handler foundation; issue #13 supplies the executable chain.

module "index-snapshot-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-index.id
  title       = "index-snapshot-request"
  description = "Memory v1 index-snapshot handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "index-snapshot" {
  space_id = tama_space.memory-index.id
  name     = "index-snapshot"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "index-snapshot" {
  count    = 0
  space_id = tama_space.memory-index.id
  class_id = module.index-snapshot-request.class.id
  chain_id = tama_chain.index-snapshot.id
  type     = "reactive"
  on       = "processing"
}
