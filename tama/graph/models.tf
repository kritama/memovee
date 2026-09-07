module "inference" {
  source              = "upmaru/base/tama//modules/inference-service"
  version             = "0.5.6"
  name                = "memory-openai"
  space_id            = tama_space.memory-inference.id
  endpoint            = "https://api.openai.com"
  api_key             = var.openai_api_key
  requests_per_second = 2
  models = [{
    identifier = "gpt-4.1-mini-2025-04-14"
    path       = "/v1/chat/completions"
  }]
}
