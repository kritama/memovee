terraform {
  required_version = ">= 1.0.0"
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "= 3.6.0"
    }
    tama = {
      source  = "upmaru/tama"
      version = "= 0.7.0"
    }
  }
}
