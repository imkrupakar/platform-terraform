terraform {
  required_version = ">= 1.6.0"
  required_providers {
    rancher2 = { source = "rancher/rancher2", version = ">= 5.0.0" }
  }
}

# Phase 1 — talk to a brand-new Rancher with the bootstrap password from tools/rancher-cluster.
provider "rancher2" {
  alias     = "bootstrap"
  api_url   = var.rancher_url
  bootstrap = true
  insecure  = var.rancher_insecure
}

# Phase 2 — admin provider (token) for anything else managed centrally (e.g. GitHub auth).
provider "rancher2" {
  alias     = "admin"
  api_url   = var.rancher_url
  token_key = rancher2_bootstrap.admin.token
  insecure  = var.rancher_insecure
}
