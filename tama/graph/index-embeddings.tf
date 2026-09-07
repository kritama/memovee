# Handler foundation; issue #13 supplies the executable chain.

module "index-embeddings-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-index.id
  title       = "index-embeddings-request"
  description = "Memory v1 index-embeddings handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "index-embeddings" {
  space_id = tama_space.memory-index.id
  name     = "index-embeddings"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "index-embeddings" {
  count    = 0
  space_id = tama_space.memory-index.id
  class_id = module.index-embeddings-request.class.id
  chain_id = tama_chain.index-embeddings.id
  type     = "reactive"
  on       = "processing"
}
