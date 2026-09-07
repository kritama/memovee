# Handler foundation; issue #12 supplies the executable chain.

module "remember-clarification-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-write.id
  title       = "remember-clarification-request"
  description = "Memory v1 remember-clarification handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "remember-clarification" {
  space_id = tama_space.memory-write.id
  name     = "remember-clarification"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "remember-clarification" {
  count    = 0
  space_id = tama_space.memory-write.id
  class_id = module.remember-clarification-request.class.id
  chain_id = tama_chain.remember-clarification.id
  type     = "reactive"
  on       = "processing"
}
