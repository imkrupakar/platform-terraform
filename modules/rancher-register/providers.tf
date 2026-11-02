terraform {
  required_providers {
    rancher2 = { source = "rancher/rancher2", version = ">= 5.0.0" }
    null     = { source = "hashicorp/null", version = "~> 3.2" }
  }
}
