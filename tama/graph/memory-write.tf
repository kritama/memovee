resource "tama_space" "memory-write" {
  name = "memory-write"
  type = "component"
}

resource "tama_space_bridge" "memory-write-to-remember" {
  space_id        = tama_space.memory-write.id
  target_space_id = module.remember.space_id
}

resource "tama_space_bridge" "memory-write-to-memory-api" {
  space_id        = tama_space.memory-write.id
  target_space_id = tama_space.memory-api.id
}

resource "tama_space_bridge" "memory-write-to-memory-inference" {
  space_id        = tama_space.memory-write.id
  target_space_id = tama_space.memory-inference.id
}

locals {
  remember_tooling_recovery = {
    capture_transport_errors = true
    consecutive_limit        = 2
    honor_retry_after_max_ms = 5000
    http_retry_on_codes      = [0, 408, 429, 500, 502, 503, 504]
    max_http_retries         = 1
    retry_delays_ms          = [0]
    retry_methods            = ["post"]
    retry_on_codes           = [422]
  }

  remember_tooling_thread = {
    limit = 5
    relations = {
      routing = "forwarding"
      focus   = ["remember-tooling"]
    }
  }
}

resource "tama_prompt" "memory-write-generation-input" {
  depends_on = [
    tama_thought_tool_modifier.memory-post-create-actor,
    tama_thought_tool_modifier.memory-post-create-origin
  ]

  space_id = tama_space.memory-write.id
  name     = "Remember Tooling"
  role     = "system"
  content  = file("${path.module}/memory-write/tooling.md")
}

resource "tama_class" "remember-tool-result" {
  space_id = tama_space.memory-write.id
  schema_json = jsonencode({
    title       = "remember-tool-result"
    description = "Correlation-checked result from one remember Tooling call."
    type        = "object"
    properties = {
      kind = {
        type = "string"
        enum = ["save", "clarification", "invalid"]
      }
      code = {
        type = ["integer", "null"]
      }
      name = {
        type = ["string", "null"]
      }
      tool_call_id = {
        type = ["string", "null"]
      }
      payload = {}
      error_code = {
        type = ["string", "null"]
      }
    }
    required             = ["kind", "code", "name", "tool_call_id", "payload", "error_code"]
    additionalProperties = false
  })
}

resource "tama_class" "memory-write-result" {
  space_id = tama_space.memory-write.id
  schema_json = jsonencode(merge(local.runtime_contracts, {
    title       = "memory-write-result"
    description = "Typed terminal remember publication produced before returning to the remember root."
    "$ref"      = "#/definitions/RememberResultPublication"
  }))
}

module "memory-write-request" {
  source      = "upmaru/base/tama//modules/forwardable-class"
  version     = "0.5.6"
  space_id    = tama_space.memory-write.id
  title       = "memory-write-request"
  description = "Memory v1 memory-write handoff; preserves origin, concept and directive provenance."
}

resource "tama_chain" "memory-write" {
  space_id = tama_space.memory-write.id
  name     = "memory-write"
}

resource "tama_modular_thought" "remember-tooling" {
  chain_id        = tama_chain.memory-write.id
  index           = 0
  relation        = "remember-tooling"
  output_class_id = var.global_schemas["tool-call"]

  module {
    reference = "tama/agentic/tooling"
    parameters = jsonencode(merge(local.remember_tooling_recovery, {
      thread = merge(local.remember_tooling_thread, {
        classes = module.remember.thread_classes
      })
    }))
  }

  faculty {
    queue_id = tama_queue.interactive.id
    priority = 0
  }
}

resource "tama_thought_context" "remember-tooling" {
  thought_id = tama_modular_thought.remember-tooling.id
  prompt_id  = tama_prompt.memory-write-generation-input.id
}

resource "tama_thought_processor" "remember-tooling" {
  thought_id = tama_modular_thought.remember-tooling.id
  model_id   = module.inference.model_ids["z-ai/glm-5.3-flash"]

  completion {
    temperature = 0.0
    tool_choice = "required"
    parameters = jsonencode({
      parallel_tool_calls = false
    })
  }
}

resource "tama_thought_tool" "memory-post-create" {
  count = local.remember_enabled ? 1 : 0

  thought_id = tama_modular_thought.remember-tooling.id
  action_id  = data.tama_action.memory_api["memory_post_create"].id

  depends_on = [tama_space_bridge.memory-write-to-memory-api]
}

resource "tama_thought_tool_modifier" "memory-post-create-actor" {
  count = local.remember_enabled ? 1 : 0

  thought_tool_id   = tama_thought_tool.memory-post-create[0].id
  index             = 0
  target            = "/body/context/actor_id"
  on_missing_parent = "error"
  on_missing_source = "error"

  source {
    type = "metadata"
    path = "actor_identifier"
  }
}

resource "tama_thought_tool_modifier" "memory-post-create-origin" {
  count = local.remember_enabled ? 1 : 0

  thought_tool_id   = tama_thought_tool.memory-post-create[0].id
  index             = 1
  target            = "/body/context/origin_identifier"
  on_missing_parent = "error"
  on_missing_source = "error"

  source {
    type = "metadata"
    path = "origin_entity_identifier"
  }
}

resource "tama_class_corpus" "remember-tooling-result" {
  class_id = var.global_schemas["tool-call"]
  name     = "Remember correlated tool result"
  template = file("${path.module}/memory-write/remember-tool-result.liquid")
}

resource "tama_modular_thought" "memory-write-route" {
  chain_id        = tama_chain.memory-write.id
  index           = 1
  relation        = "tool-route"
  output_class_id = var.global_schemas["forwarding"]

  module {
    reference = "tama/concepts/dispatch"
    parameters = jsonencode({
      module = {
        relation        = "remember-tooling"
        pointer         = "/messages/1/name"
        input_selection = "latest"
      }
    })
  }

  faculty {
    queue_id = tama_queue.interactive.id
    priority = 0
  }
}

resource "tama_thought_module_input" "memory-write-route" {
  thought_id      = tama_modular_thought.memory-write-route.id
  class_corpus_id = tama_class_corpus.remember-tooling-result.id
  type            = "concept"
}

resource "tama_thought_path" "memory-write-route-save" {
  thought_id      = tama_modular_thought.memory-write-route.id
  target_class_id = module.remember-save-request.class.id
  parameters = jsonencode({
    path = {
      values  = ["memory_post_create"]
      default = false
    }
  })
}

resource "tama_thought_path" "memory-write-route-clarification" {
  thought_id      = tama_modular_thought.memory-write-route.id
  target_class_id = module.remember-clarification-request.class.id
  parameters = jsonencode({
    path = {
      values  = ["memo"]
      default = false
    }
  })
}

resource "tama_thought_path" "memory-write-route-invalid" {
  thought_id      = tama_modular_thought.memory-write-route.id
  target_class_id = module.remember-invalid-response-request.class.id
  parameters = jsonencode({
    path = {
      values  = []
      default = true
    }
  })
}

resource "tama_node" "memory-write" {
  count    = local.remember_enabled ? 1 : 0
  space_id = tama_space.memory-write.id
  class_id = module.memory-write-request.class.id
  chain_id = tama_chain.memory-write.id
  type     = "reactive"
  on       = "processing"

  depends_on = [
    tama_thought_context.remember-tooling,
    tama_thought_processor.remember-tooling,
    tama_thought_tool_modifier.memory-post-create-actor,
    tama_thought_tool_modifier.memory-post-create-origin,
    tama_thought_module_input.memory-write-route,
    tama_thought_path.memory-write-route-save,
    tama_thought_path.memory-write-route-clarification,
    tama_thought_path.memory-write-route-invalid
  ]
}
