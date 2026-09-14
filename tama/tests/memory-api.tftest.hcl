# Mock-provider plans are static evidence only. No remote resources or secrets.
mock_provider "tama" {}

run "unknown_operation_rejected" {
  command = plan
  module { source = "./graph" }
  variables {
    global_space_id             = "fixture-global"
    global_schemas              = { forwarding = "fixture-forwarding" }
    context_metadata_corpus_id  = "fixture-context"
    action_call_json_corpus_id  = "fixture-action"
    openrouter_api_key          = "fixture-only-never-a-real-credential"
    memory_api_specification_id = "fixture-specification"
    memory_api_operations       = ["MemoveeWeb.Tama.Memory.PostController.create"]
  }
  expect_failures = [var.memory_api_operations]
}
