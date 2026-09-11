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
    condition     = length(module.memory.interfaces.stages) == 31
    error_message = "Every fixed stage needs an independent handler interface."
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
