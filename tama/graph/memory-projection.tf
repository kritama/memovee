# Handler foundation; issue #13 supplies the executable chain.

resource "tama_class" "memory-projection-request" {
  space_id    = tama_space.memory-index.id
  schema_json = jsonencode(jsondecode(file("${path.module}/schemas/projection-request.json")))
}

resource "tama_chain" "memory-projection" {
  space_id = tama_space.memory-index.id
  name     = "memory-projection"
}

# Keep the handler disabled until its terminal paths are implemented.
resource "tama_node" "memory-projection" {
  count    = 0
  space_id = tama_space.memory-index.id
  class_id = tama_class.memory-projection-request.id
  chain_id = tama_chain.memory-projection.id
  type     = "reactive"
  on       = "processing"
}
