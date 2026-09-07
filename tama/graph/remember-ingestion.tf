# Handler foundation; issue #12 supplies the executable chain.

module "remember-ingestion-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-write.id
  title       = "remember-ingestion-request"
  description = "Memory v1 remember-ingestion handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "remember-ingestion" {
  space_id = tama_space.memory-write.id
  name     = "remember-ingestion"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "remember-ingestion" {
  count    = 0
  space_id = tama_space.memory-write.id
  class_id = module.remember-ingestion-request.class.id
  chain_id = tama_chain.remember-ingestion.id
  type     = "reactive"
  on       = "processing"
}
