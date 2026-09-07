module "inference" {
  source              = "upmaru/base/tama//modules/inference-service"
  version             = "0.5.6"
  name                = "memory-openrouter"
  space_id            = tama_space.memory-inference.id
  endpoint            = "https://openrouter.ai/api/v1"
  api_key             = var.openrouter_api_key
  requests_per_second = 2
  models = [{
    identifier = "openai/gpt-4.1-mini"
    path       = "/chat/completions"
  }]
}
