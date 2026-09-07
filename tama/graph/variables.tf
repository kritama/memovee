variable "global_space_id" { type = string }
variable "global_schemas" { type = map(string) }
variable "context_metadata_corpus_id" { type = string }
variable "action_call_json_corpus_id" { type = string }
variable "openrouter_api_key" {
  type      = string
  sensitive = true
}
