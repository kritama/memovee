locals {
  contracts = jsondecode(file("${path.module}/schemas/memory-contract.v1.json"))
}
