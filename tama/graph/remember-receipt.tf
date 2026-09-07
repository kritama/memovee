# Handler foundation; issue #12 supplies the executable chain.

module "remember-receipt-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-write.id
  title       = "remember-receipt-request"
  description = "Memory v1 remember-receipt handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "remember-receipt" {
  space_id = tama_space.memory-write.id
  name     = "remember-receipt"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "remember-receipt" {
  count    = 0
  space_id = tama_space.memory-write.id
  class_id = module.remember-receipt-request.class.id
  chain_id = tama_chain.remember-receipt.id
  type     = "reactive"
  on       = "processing"
}
