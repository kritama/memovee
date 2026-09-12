locals {
  contracts = jsondecode(file("${path.module}/schemas/memory-contract.v1.json"))

  # Tama 0.14.0 validates output classes with JsonXema, which supports JSON
  # Schema through draft-07. Keep the canonical 2020-12 contract in source and
  # project its definition vocabulary and null-codepoint regex escapes to the
  # draft-07/PCRE syntax JsonXema accepts for runtime validation.
  runtime_contracts = jsondecode(replace(
    replace(
      replace(
        jsonencode(merge(local.contracts, {
          "$schema" = "http://json-schema.org/draft-07/schema#"
        })),
        "\"$defs\":",
        "\"definitions\":"
      ),
      "#/$defs/",
      "#/definitions/"
    ),
    "\\\\u0000",
    "\\\\x{0000}"
  ))
}
