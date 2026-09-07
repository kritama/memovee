# Handler foundation; issue #12 supplies the executable chain.

module "remember-invalid-response-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-write.id
  title       = "remember-invalid-response-request"
  description = "Memory v1 remember-invalid-response handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "remember-invalid-response" {
  space_id = tama_space.memory-write.id
  name     = "remember-invalid-response"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "remember-invalid-response" {
  count    = 0
  space_id = tama_space.memory-write.id
  class_id = module.remember-invalid-response-request.class.id
  chain_id = tama_chain.remember-invalid-response.id
  type     = "reactive"
  on       = "processing"
}
