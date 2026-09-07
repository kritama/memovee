# Handler foundation; issue #12 supplies the executable chain.

module "remember-status-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-write.id
  title       = "remember-status-request"
  description = "Memory v1 remember-status handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "remember-status" {
  space_id = tama_space.memory-write.id
  name     = "remember-status"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "remember-status" {
  count    = 0
  space_id = tama_space.memory-write.id
  class_id = module.remember-status-request.class.id
  chain_id = tama_chain.remember-status.id
  type     = "reactive"
  on       = "processing"
}
