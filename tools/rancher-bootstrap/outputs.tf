output "rancher_url" {
  value = var.rancher_url
}

# API token each fleet cluster stack uses (modules/rancher-register var.rancher_token).
# For production, mint a dedicated scoped token instead of reusing the bootstrap token.
output "rancher_api_token" {
  description = "Rancher admin API token for per-cluster registration."
  value       = rancher2_bootstrap.admin.token
  sensitive   = true
}
