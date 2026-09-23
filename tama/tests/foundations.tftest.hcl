# Mock-provider plans are static evidence only. No remote resources or secrets.
mock_provider "tama" {}
mock_provider "http" {
  mock_data "http" {
    defaults = {
      response_body = jsonencode({
        openapi = "3.0.0"
        info    = { title = "Memovee Tama API", version = "0.1.2" }
        servers = [{ url = "https://app.localhost" }]
        paths   = {}
      })
    }
  }
}

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
