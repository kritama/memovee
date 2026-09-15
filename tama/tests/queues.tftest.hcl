# Mock-provider plans are static evidence only. No remote resources or secrets.
mock_provider "tama" {}

run "baseline_scribe_queues_are_explicit" {
  command = plan
  variables {
    memory_openrouter_api_key = "fixture-only-never-a-real-credential"
  }

  assert {
    condition = toset([
      tama_queue.default.name,
      tama_queue.branches.name,
      tama_queue.steps.name,
      tama_queue.flows.name,
      tama_queue.specifications.name,
      tama_queue.agentic.name,
      tama_queue.entities.name,
      tama_queue.concepts.name,
      tama_queue.classes.name,
      tama_queue.actions.name,
      tama_queue.identities.name,
      ]) == toset([
      "default",
      "branches",
      "steps",
      "flows",
      "specifications",
      "agentic",
      "entities",
      "concepts",
      "classes",
      "actions",
      "identities",
    ])
    error_message = "The Terraform root must provision the exact Tama baseline queue set."
  }

  assert {
    condition = alltrue([
      tama_queue.default.role == "scribe",
      tama_queue.branches.role == "scribe",
      tama_queue.steps.role == "scribe",
      tama_queue.flows.role == "scribe",
      tama_queue.specifications.role == "scribe",
      tama_queue.agentic.role == "scribe",
      tama_queue.entities.role == "scribe",
      tama_queue.concepts.role == "scribe",
      tama_queue.classes.role == "scribe",
      tama_queue.actions.role == "scribe",
      tama_queue.identities.role == "scribe",
    ])
    error_message = "Core runtime queues must use the scribe role so mixed-role nodes load them with oracle queues."
  }
}
