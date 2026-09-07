# Handler foundation; issue #13 supplies the executable chain.

module "index-embedding-inputs-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-index.id
  title       = "index-embedding-inputs-request"
  description = "Memory v1 index-embedding-inputs handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "index-embedding-inputs" {
  space_id = tama_space.memory-index.id
  name     = "index-embedding-inputs"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "index-embedding-inputs" {
  count    = 0
  space_id = tama_space.memory-index.id
  class_id = module.index-embedding-inputs-request.class.id
  chain_id = tama_chain.index-embedding-inputs.id
  type     = "reactive"
  on       = "processing"
}
