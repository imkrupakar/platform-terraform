###############################################################################
# tools/rancher-bootstrap — ONE-TIME Rancher control-plane setup.
# Sets the admin password, mints an API token, and (optionally) enables GitHub auth. The API token
# is consumed by EACH fleet cluster's stack (via modules/rancher-register) to register itself.
#
# Run once, after tools/rancher-cluster. Per-cluster registration + Projects live with each cluster.
###############################################################################

resource "rancher2_bootstrap" "admin" {
  provider         = rancher2.bootstrap
  initial_password = var.rancher_bootstrap_password
  password         = var.rancher_admin_password
  token_update     = true
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
