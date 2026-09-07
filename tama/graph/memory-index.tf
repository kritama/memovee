resource "tama_space" "memory-index" {
  name = "memory-index"
  type = "component"
}

resource "tama_space_bridge" "memory-index-to-memory-api" {
  space_id        = tama_space.memory-index.id
  target_space_id = tama_space.memory-api.id
}

resource "tama_space_bridge" "memory-index-to-memory-inference" {
  space_id        = tama_space.memory-index.id
  target_space_id = tama_space.memory-inference.id
}

# Stage owners bind this user message in addition to their system prompt.
resource "tama_prompt" "memory-index-generation-input" {
  space_id = tama_space.memory-index.id
  name     = "Memory evidence"
  role     = "user"
  content  = file("${path.module}/corpora/generation-input.md")
}

resource "tama_class" "index-description-provider" {
  space_id    = tama_space.memory-index.id
  schema_json = jsonencode(jsondecode(file("${path.module}/schemas/description-provider.json")))
}
