resource "tama_space" "memory-api" {
  name = "memory-api"
  type = "component"
}

# The application owns the OpenAPI document; Terraform owns its Tama registration.
variable "memory_api_openapi_url" {
  type        = string
  default     = "https://app.localhost/tama/openapi"
  description = "URL of the Memovee Tama OpenAPI document."
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
      "memory_post_create",
      "memory_search", "memory_index_upsert"
    ]))) == 0
    error_message = "Only explicit Memory v1 operation IDs may be resolved."
  }
}

variable "memory_api_client_id" {
  type        = string
  default     = null
  description = "Client ID of the Memovee Agent API token used by this source identity."
}

variable "memory_api_client_secret" {
  type        = string
  default     = null
  sensitive   = true
  description = "Secret of the Memovee Agent API token used by this source identity."
}

locals {
  memory_api_identity_configured = (
    var.memory_api_client_id != null &&
    nonsensitive(var.memory_api_client_secret != null)
  )

  remember_enabled = (
    var.memory_api_source_slug != null &&
    contains(var.memory_api_operations, "memory_post_create") &&
    local.memory_api_identity_configured
  )
}

data "http" "memory_api" {
  url = var.memory_api_openapi_url
}

resource "tama_specification" "memory_api" {
  space_id = tama_space.memory-api.id
  endpoint = var.memory_api_openapi_url
  version  = "0.1.2"
  schema   = jsonencode(jsondecode(data.http.memory_api.response_body))

  wait_for {
    field {
      name = "current_state"
      in   = ["completed", "failed"]
    }
  }
}

resource "tama_source_identity" "memory_api" {
  count            = local.memory_api_identity_configured ? 1 : 0
  specification_id = tama_specification.memory_api.id
  identifier       = "bearer_auth"
  api_key          = "${var.memory_api_client_id}.${var.memory_api_client_secret}"

  validation {
    path   = "/tama/health"
    method = "GET"
    codes  = [200]
  }

  wait_for {
    field {
      name = "current_state"
      in   = ["active"]
    }
  }
}

data "tama_source" "memory_api" {
  count            = var.memory_api_source_slug != null ? 1 : 0
  specification_id = tama_specification.memory_api.id
  slug             = var.memory_api_source_slug
}
resource "tama_source_limit" "memory_api" {
  count       = var.memory_api_source_slug != null ? 1 : 0
  source_id   = data.tama_source.memory_api[0].id
  scale_count = 1
  scale_unit  = "seconds"
  value       = 10
}
data "tama_action" "memory_api" {
  for_each         = var.memory_api_operations
  specification_id = tama_specification.memory_api.id
  identifier       = each.key
}
