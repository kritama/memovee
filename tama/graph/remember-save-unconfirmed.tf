# Handler foundation; issue #12 supplies the executable chain.

module "remember-save-unconfirmed-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-write.id
  title       = "remember-save-unconfirmed-request"
  description = "Memory v1 remember-save-unconfirmed handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "remember-save-unconfirmed" {
  space_id = tama_space.memory-write.id
  name     = "remember-save-unconfirmed"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "remember-save-unconfirmed" {
  count    = 0
  space_id = tama_space.memory-write.id
  class_id = module.remember-save-unconfirmed-request.class.id
  chain_id = tama_chain.remember-save-unconfirmed.id
  type     = "reactive"
  on       = "processing"
}
