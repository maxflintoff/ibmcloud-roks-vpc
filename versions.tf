terraform {
  required_version = ">= 0.13.3"
  required_providers {
    ibm = {
      source  = "ibm-cloud/ibm"
      version = "1.13.1"
    }
    external = {
      source = "hashicorp/external"
    }
    null = {
      source = "hashicorp/null"
    }
  }
}