# Handler foundation; issue #15 supplies the executable chain.

module "recall-query-embedding-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-query.id
  title       = "recall-query-embedding-request"
  description = "Memory v1 recall-query-embedding handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "recall-query-embedding" {
  space_id = tama_space.memory-query.id
  name     = "recall-query-embedding"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "recall-query-embedding" {
  count    = 0
  space_id = tama_space.memory-query.id
  class_id = module.recall-query-embedding-request.class.id
  chain_id = tama_chain.recall-query-embedding.id
  type     = "reactive"
  on       = "processing"
}
