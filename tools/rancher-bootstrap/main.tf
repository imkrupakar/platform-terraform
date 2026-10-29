###############################################################################
# tools/rancher-bootstrap — ONE-TIME Rancher control-plane setup.
# Sets the admin password, mints an API token, and (optionally) enables GitHub auth. The API token
# is consumed by EACH fleet cluster's stack (via modules/rancher-register) to register itself.
#
# Run once, after tools/rancher-cluster. Per-cluster registration + Projects live with each cluster.
###############################################################################
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

resource "rancher2_bootstrap" "admin" {
  provider         = rancher2.bootstrap
  initial_password = var.rancher_bootstrap_password
  password         = var.rancher_admin_password
  token_update     = true
}

# Phase 2 — admin provider (token) for anything else managed centrally (e.g. GitHub auth).
provider "rancher2" {
  alias     = "admin"
  api_url   = var.rancher_url
  token_key = rancher2_bootstrap.admin.token
  insecure  = var.rancher_insecure
}

# Optional (gated): GitHub as the IdP. Needs a GitHub OAuth App (callback https://<host>/verify-auth).
resource "rancher2_auth_config_github" "github" {
  count         = var.enable_github_auth ? 1 : 0
  provider      = rancher2.admin
  hostname      = "github.com"
  client_id     = var.github_client_id
  client_secret = var.github_client_secret
  access_mode   = "unrestricted" # POC; tighten with restricted + allowed_principal_ids later
}
