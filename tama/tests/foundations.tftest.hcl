# Mock-provider plans are static evidence only. No remote resources or secrets.
mock_provider "tama" {}

run "staged_foundations" {
  command = plan
  variables {
    memory_openrouter_api_key = "fixture-only-never-a-real-credential"
  }
  assert {
    condition     = module.memory.interfaces.ready == false
    error_message = "Scaffolding must not advertise a ready graph."
  }
  assert {
    condition = length(setintersection(
      toset(keys(module.memory.interfaces.stages)),
      toset([
        "remember-candidate",
        "remember-invalid-candidate",
        "remember-status",
        "remember-retry-save"
      ])
    )) == 0
    error_message = "Obsolete remember candidate, status, and retry handlers must stay removed."
  }
  assert {
    condition     = toset(keys(module.memory.interfaces.roots)) == toset(["remember", "recall"])
    error_message = "Root messaging slugs must remain remember and recall."
  }
  assert {
    condition     = module.memory.interfaces.stages["memory-projection"].relation == "snapshot"
    error_message = "Background insertion must start at snapshot, outside messaging roots."
  }
}
