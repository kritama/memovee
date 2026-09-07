# Handler foundation; issue #12 supplies the executable chain.

module "remember-recovery-state-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-write.id
  title       = "remember-recovery-state-request"
  description = "Memory v1 remember-recovery-state handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "remember-recovery-state" {
  space_id = tama_space.memory-write.id
  name     = "remember-recovery-state"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "remember-recovery-state" {
  count    = 0
  space_id = tama_space.memory-write.id
  class_id = module.remember-recovery-state-request.class.id
  chain_id = tama_chain.remember-recovery-state.id
  type     = "reactive"
  on       = "processing"
}
