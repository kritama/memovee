resource "tama_space" "memory-api" {
  name = "memory-api"
  type = "component"
}

# #10 exports the real OpenAPI document. #12/#13/#15 add action bindings only
# when their operations exist. Never import a stub API as a successful backend.
variable "memory_api_specification_id" {
  type        = string
  default     = null
  description = "Existing imported Memovee specification ID, supplied after #10."
}
variable "memory_api_source_slug" {
  type        = string
  default     = null
  description = "Exact server source slug from the imported OpenAPI server."
}
variable "memory_api_operations" {
  type    = set(string)
  default = []
  validation {
    condition = length(setsubtract(var.memory_api_operations, toset([
      "memory_ingestion_open", "memory_ingestion_status", "memory_post_create",
      "memory_search", "memory_projection_snapshot", "memory_projection_complete"
    ]))) == 0
    error_message = "Only explicit Memory v1 operation IDs may be resolved."
  }
}
data "tama_source" "memory_api" {
  count            = var.memory_api_specification_id != null && var.memory_api_source_slug != null ? 1 : 0
  specification_id = var.memory_api_specification_id
  slug             = var.memory_api_source_slug
}
resource "tama_source_limit" "memory_api" {
  count       = length(data.tama_source.memory_api)
  source_id   = data.tama_source.memory_api[0].id
  scale_count = 1
  scale_unit  = "seconds"
  value       = 10
}
data "tama_action" "memory_api" {
  for_each         = var.memory_api_operations
  specification_id = var.memory_api_specification_id
  identifier       = each.key
  lifecycle {
    precondition {
      condition     = var.memory_api_specification_id != null
      error_message = "Import the real Memovee specification before resolving operation IDs."
    }
  }
}
