resource "tama_queue" "interactive" {
  name        = "memory-interactive"
  role        = "oracle"
  concurrency = 4
}
resource "tama_queue" "index" {
  name        = "memory-index"
  role        = "oracle"
  concurrency = 2
}
