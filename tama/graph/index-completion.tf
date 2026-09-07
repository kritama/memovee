# Handler foundation; issue #13 supplies the executable chain.

module "index-completion-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-index.id
  title       = "index-completion-request"
  description = "Memory v1 index-completion handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "index-completion" {
  space_id = tama_space.memory-index.id
  name     = "index-completion"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "index-completion" {
  count    = 0
  space_id = tama_space.memory-index.id
  class_id = module.index-completion-request.class.id
  chain_id = tama_chain.index-completion.id
  type     = "reactive"
  on       = "processing"
}
