# Handler foundation; issue #12 supplies the executable chain.

module "remember-failure-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-write.id
  title       = "remember-failure-request"
  description = "Memory v1 remember-failure handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "remember-failure" {
  space_id = tama_space.memory-write.id
  name     = "remember-failure"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "remember-failure" {
  count    = 0
  space_id = tama_space.memory-write.id
  class_id = module.remember-failure-request.class.id
  chain_id = tama_chain.remember-failure.id
  type     = "reactive"
  on       = "processing"
}
