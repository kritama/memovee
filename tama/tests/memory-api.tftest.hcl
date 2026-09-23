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

run "unknown_operation_rejected" {
  command = plan
  module { source = "./graph" }
  variables {
    global_space_id = "fixture-global"
    global_schemas = {
      forwarding = "fixture-forwarding"
      tool-call  = "fixture-tool-call"
    }
    context_metadata_corpus_id = "fixture-context"
    action_call_json_corpus_id = "fixture-action"
    openrouter_api_key         = "fixture-only-never-a-real-credential"
    memory_api_openapi_url     = "https://app.localhost/tama/openapi"
    memory_api_operations      = ["MemoveeWeb.Tama.Memory.PostController.create"]
  }
  expect_failures = [var.memory_api_operations]
}
