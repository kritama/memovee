locals {
  contracts = jsondecode(file("${path.module}/schemas/schemas.json"))
}
