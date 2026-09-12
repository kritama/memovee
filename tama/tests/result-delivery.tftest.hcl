# Mock-provider plans are static evidence only. No remote resources or secrets.
mock_provider "tama" {}

run "result_publishers_are_configured" {
  command = plan
  variables {
    memory_openrouter_api_key = "fixture-only-never-a-real-credential"
  }
  assert {
    condition     = module.memory.interfaces.result_fixtures_enabled == false
    error_message = "Deterministic result fixture entry points must default to disabled."
  }
  assert {
    condition = alltrue([
      module.memory.interfaces.results.remember.publisher == "tama/agentic/result",
      module.memory.interfaces.results.recall.publisher == "tama/agentic/result"
    ])
    error_message = "Both roots must use Tama's built-in terminal result publisher."
  }
}

run "result_fixture_entrypoints_are_explicit" {
  command = plan
  variables {
    memory_openrouter_api_key      = "fixture-only-never-a-real-credential"
    memory_result_fixtures_enabled = true
  }
  assert {
    condition     = module.memory.interfaces.result_fixtures_enabled == true
    error_message = "Live result fixtures must require an explicit test-only opt in."
  }
  assert {
    condition     = module.memory.interfaces.ready == false
    error_message = "Fixture entry points must not advertise production readiness."
  }
}
