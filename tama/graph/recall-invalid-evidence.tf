# Handler foundation; issue #15 supplies the executable chain.

module "recall-invalid-evidence-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-query.id
  title       = "recall-invalid-evidence-request"
  description = "Memory v1 recall-invalid-evidence handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "recall-invalid-evidence" {
  space_id = tama_space.memory-query.id
  name     = "recall-invalid-evidence"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "recall-invalid-evidence" {
  count    = 0
  space_id = tama_space.memory-query.id
  class_id = module.recall-invalid-evidence-request.class.id
  chain_id = tama_chain.recall-invalid-evidence.id
  type     = "reactive"
  on       = "processing"
}
