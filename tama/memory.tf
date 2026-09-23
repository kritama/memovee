# Memory owns a child module, never a second Terraform state or global space.
module "memory" {
  source = "./graph"

  global_space_id            = module.global.space.id
  global_schemas             = { for name, class in module.global.schemas : name => class.id }
  context_metadata_corpus_id = module.global.context_metadata_corpus_id
  action_call_json_corpus_id = module.global.action_call_json_corpus_id
  enable_result_fixtures     = var.memory_result_fixtures_enabled
  openrouter_api_key         = var.memory_openrouter_api_key
  memory_api_openapi_url     = var.memory_api_openapi_url
  memory_api_source_slug     = var.memory_api_source_slug
  memory_api_operations      = var.memory_api_operations
  memory_api_client_id       = var.memory_api_client_id
  memory_api_client_secret   = var.memory_api_client_secret
}
variable "memory_openrouter_api_key" {
  type        = string
  sensitive   = true
  description = "Operator OpenRouter credential; supplied through TF_VAR_memory_openrouter_api_key."
}
output "memory_interfaces" {
  value = module.memory.interfaces
}
variable "memory_api_openapi_url" {
  type        = string
  default     = "https://app.localhost/tama/openapi"
  description = "Public URL of the Memovee Tama OpenAPI document."
}
variable "memory_api_source_slug" {
  type        = string
  default     = null
  description = "Exact source slug from the imported Memovee OpenAPI server."
}
variable "memory_api_operations" {
  type        = set(string)
  default     = []
  description = "Only implemented backend operation IDs, never guessed controller names."
}

variable "memory_api_client_id" {
  type        = string
  default     = null
  description = "Client ID of the Memovee Agent API token used by the memory API source."
}

variable "memory_api_client_secret" {
  type        = string
  default     = null
  sensitive   = true
  description = "Secret of the Memovee Agent API token used by the memory API source."
}

variable "memory_result_fixtures_enabled" {
  type        = bool
  default     = false
  nullable    = false
  description = "Enables deterministic remember/recall result fixtures for an authorized live integration trace."
}
