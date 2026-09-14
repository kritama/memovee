variable "global_space_id" { type = string }
variable "global_schemas" { type = map(string) }
variable "context_metadata_corpus_id" { type = string }
variable "action_call_json_corpus_id" { type = string }
variable "enable_result_fixtures" {
  type        = bool
  default     = false
  description = "Enables deterministic message-to-result fixture entry points for integration testing only."
}
variable "openrouter_api_key" {
  type      = string
  sensitive = true
}
