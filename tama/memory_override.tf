# Application-owned provider constraint. Terraform override semantics replace the
# generated required_providers entry without modifying Tama Kit managed hashes.
terraform {
  required_providers {
    tama = {
      source  = "upmaru/tama"
      version = "= 0.7.0"
    }
  }
}
