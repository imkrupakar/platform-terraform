subscription_id            = "c556d760-610e-4ac0-a522-dc67de95d763"
resource_group_name        = "rg-platform-sbx-cus"
region                     = "centralus"
cluster_name               = "aks-sbx-cus"
acr_name                   = "acrplatsbxcus14462b"
environment                = "sbx"
node_count                 = 2
node_vm_size               = "Standard_D4ds_v6"
enable_argocd              = true
argocd_chart_version       = "10.10.1"
gateway_api_version        = "1.6.3"
github_app_id              = "5379839"
github_app_installation_id = "172998649"
# github_app_private_key supplied via TF_VAR_github_app_private_key="$(cat argocd-app.pem)"

# --- Rancher registration (presence of `rancher` enables it) ---
rancher = {
  url = "https://rancher-platform-tools-cus.centralus.cloudapp.azure.com"
  # insecure defaults to true (self-signed Rancher)
}
# rancher_token supplied via TF_VAR_rancher_token (Rancher API token; keep out of VCS)

# 1:1 tenant=Project. Empty group_principal_id => create the Project only (no RBAC binding) — used to
# test the namespace->Project mapping before Rancher GitHub/IdP auth is wired. Add the
# github_team://<id> principal later to also grant project-member to that GitHub team.
tenants = {
  "team-alpha" = { group_principal_id = "" }
}
platform_gitops_revision = "main"
