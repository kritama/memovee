# Mock-provider plans are static evidence only. No remote resources or secrets.
mock_provider "tama" {}

run "remember_ingestion_topology" {
  command = plan

  module {
    source = "./graph"
  }

  variables {
    global_space_id = "fixture-global"
    global_schemas = {
      forwarding = "fixture-forwarding"
      tool-call  = "fixture-tool-call"
    }
    context_metadata_corpus_id  = "fixture-context"
    action_call_json_corpus_id  = "fixture-action"
    openrouter_api_key          = "fixture-only-never-a-real-credential"
    memory_api_specification_id = "fixture-specification"
    memory_api_source_slug      = "fixture-source"
    memory_api_operations       = ["memory_post_create"]
  }

  assert {
    condition = alltrue([
      length(tama_node.remember-forward) == 1,
      length(tama_node.memory-write) == 1
    ])
    error_message = "Configured remember ingestion must enable both root and component entry nodes."
  }

  assert {
    condition = alltrue([
      local.remember_tooling_recovery.capture_transport_errors == true,
      local.remember_tooling_recovery.consecutive_limit == 2,
      local.remember_tooling_recovery.honor_retry_after_max_ms == 5000,
      local.remember_tooling_recovery.http_retry_on_codes == [0, 408, 429, 500, 502, 503, 504],
      local.remember_tooling_recovery.max_http_retries == 1,
      local.remember_tooling_recovery.retry_delays_ms == [0],
      local.remember_tooling_recovery.retry_methods == ["post"],
      local.remember_tooling_recovery.retry_on_codes == [422],
      local.remember_tooling_thread.limit == 5,
      local.remember_tooling_thread.relations.focus == ["remember-tooling"],
      local.remember_tooling_thread.relations.routing == "forwarding"
    ])
    error_message = "Remember Tooling must use the bounded exact-request POST recovery policy."
  }

  assert {
    condition = alltrue([
      tama_modular_thought.remember-tooling.module.reference == "tama/agentic/tooling",
      tama_thought_processor.remember-tooling.completion.tool_choice == "required",
      jsondecode(tama_thought_processor.remember-tooling.completion.parameters).parallel_tool_calls == false,
      length(tama_thought_tool.memory-post-create) == 1,
      data.tama_action.memory_api["memory_post_create"].identifier == "memory_post_create",
      var.memory_api_operations == toset(["memory_post_create"])
    ])
    error_message = "Remember Tooling must require one serial external memory_post_create action."
  }

  assert {
    condition = alltrue([
      strcontains(tama_prompt.memory-write-generation-input.content, "\"context\": {}"),
      strcontains(tama_prompt.memory-write-generation-input.content, "\"title\": null"),
      strcontains(tama_prompt.memory-write-generation-input.content, "\"channel\": \"agent\""),
      strcontains(tama_prompt.memory-write-generation-input.content, "\"derived_from_post_ids\": []")
    ])
    error_message = "The remember prompt must show a complete modifier-compatible Memory v1 request envelope."
  }

  assert {
    condition = alltrue([
      length(tama_thought_tool_modifier.memory-post-create-actor) == 1,
      tama_thought_tool_modifier.memory-post-create-actor[0].index == 0,
      tama_thought_tool_modifier.memory-post-create-actor[0].target == "/body/context/actor_id",
      tama_thought_tool_modifier.memory-post-create-actor[0].source.type == "metadata",
      tama_thought_tool_modifier.memory-post-create-actor[0].source.path == "actor_identifier",
      tama_thought_tool_modifier.memory-post-create-actor[0].on_missing_parent == "error",
      tama_thought_tool_modifier.memory-post-create-actor[0].on_missing_source == "error",
      length(tama_thought_tool_modifier.memory-post-create-origin) == 1,
      tama_thought_tool_modifier.memory-post-create-origin[0].index == 1,
      tama_thought_tool_modifier.memory-post-create-origin[0].target == "/body/context/origin_identifier",
      tama_thought_tool_modifier.memory-post-create-origin[0].source.type == "metadata",
      tama_thought_tool_modifier.memory-post-create-origin[0].source.path == "origin_entity_identifier",
      tama_thought_tool_modifier.memory-post-create-origin[0].on_missing_parent == "error",
      tama_thought_tool_modifier.memory-post-create-origin[0].on_missing_source == "error"
    ])
    error_message = "Remember must fail closed while injecting trusted actor and origin metadata."
  }

  assert {
    condition = alltrue([
      jsondecode(tama_modular_thought.memory-write-route.module.parameters).module.relation == "remember-tooling",
      jsondecode(tama_modular_thought.memory-write-route.module.parameters).module.pointer == "/messages/1/name",
      jsondecode(tama_modular_thought.memory-write-route.module.parameters).module.input_selection == "latest",
      jsondecode(tama_thought_path.memory-write-route-save.parameters).path.values == ["memory_post_create"],
      jsondecode(tama_thought_path.memory-write-route-clarification.parameters).path.values == ["memo"],
      jsondecode(tama_thought_path.memory-write-route-invalid.parameters).path.default == true
    ])
    error_message = "The latest persisted Tooling result must route to save, clarification, and invalid handlers."
  }

  assert {
    condition = alltrue([
      tama_modular_thought.remember-save-tool-result.relation == "tool-result",
      tama_modular_thought.remember-clarification-tool-result.relation == "tool-result"
    ])
    error_message = "Save and clarification handlers must correlation-check their selected Tooling result."
  }

  assert {
    condition = alltrue([
      jsondecode(tama_thought_path.remember-save-route-receipt.parameters).path.default == true,
      jsondecode(tama_thought_path.remember-save-route-unconfirmed.parameters).path.values == ["save_unconfirmed"],
      toset(jsondecode(tama_thought_path.remember-save-route-failure.parameters).path.values) == toset(["save_rejected", "save_unavailable"]),
      jsondecode(tama_thought_path.remember-save-route-invalid.parameters).path.values == ["invalid_tool_result"]
    ])
    error_message = "Save outcomes must route saved, uncertain, HTTP-failure, and invalid results explicitly."
  }

  assert {
    condition = alltrue([
      tama_modular_thought.remember-receipt-forward.relation == "result-forwarding",
      tama_modular_thought.remember-clarification-forward.relation == "result-forwarding",
      tama_modular_thought.remember-failure-forward.relation == "result-forwarding",
      tama_modular_thought.remember-save-unconfirmed-forward.relation == "result-forwarding",
      tama_modular_thought.remember-invalid-response-forward.relation == "result-forwarding"
    ])
    error_message = "Every remember terminal must return to the existing root result publisher."
  }

  assert {
    condition = length(setintersection(
      toset(keys(output.interfaces.stages)),
      toset([
        "remember-candidate",
        "remember-invalid-candidate",
        "remember-status",
        "remember-retry-save"
      ])
    )) == 0
    error_message = "Obsolete candidate, status, and graph-level retry stages must be absent."
  }


  assert {
    condition = alltrue([
      length(tama_node.remember-result-fixture-root) == 0,
      length(tama_node.remember-result-fixture-component) == 0
    ])
    error_message = "The deterministic result fixture path must remain disabled by default."
  }
}

run "remember_ingestion_requires_api_binding" {
  command = plan

  module {
    source = "./graph"
  }

  variables {
    global_space_id = "fixture-global"
    global_schemas = {
      forwarding = "fixture-forwarding"
      tool-call  = "fixture-tool-call"
    }
    context_metadata_corpus_id = "fixture-context"
    action_call_json_corpus_id = "fixture-action"
    openrouter_api_key         = "fixture-only-never-a-real-credential"
  }

  assert {
    condition = alltrue([
      length(tama_node.remember-forward) == 0,
      length(tama_node.memory-write) == 0,
      length(tama_thought_tool.memory-post-create) == 0
    ])
    error_message = "Production remember ingress must stay disabled until memory_post_create is configured."
  }
}
