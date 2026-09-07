# Handler foundation; issue #13 supplies the executable chain.

module "index-description-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-index.id
  title       = "index-description-request"
  description = "Memory v1 index-description handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "index-description" {
  space_id = tama_space.memory-index.id
  name     = "index-description"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "index-description" {
  count    = 0
  space_id = tama_space.memory-index.id
  class_id = module.index-description-request.class.id
  chain_id = tama_chain.index-description.id
  type     = "reactive"
  on       = "processing"
}
