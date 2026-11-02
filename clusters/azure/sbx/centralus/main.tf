# clusters/azure/sbx/centralus — provision the AKS cluster + ACR, then bootstrap Argo CD.
# Single `terraform apply` provisions everything (cluster, Gateway API CRDs, Argo CD) in one pass.
# First bring-up of a brand-new cluster: apply once with enable_argocd=false to stand up infra,
# create the GitHub App, then apply with enable_argocd=true and the github_app_* vars set.
# Provider + required_providers config lives in providers.tf.

module "cluster" {
  source              = "../../../../modules/aks-cluster"
  name                = var.cluster_name
  region              = var.region
  resource_group_name = var.resource_group_name
  node_count          = var.node_count
  node_vm_size        = var.node_vm_size
  tags                = local.common_tags
}

# Nonprod ACR in the same platform RG; AKS kubelet identity gets AcrPull.
resource "azurerm_container_registry" "this" {
  name                = var.acr_name
  resource_group_name = module.cluster.resource_group_name
  location            = var.region
  sku                 = "Standard"
  admin_enabled       = false
  tags                = merge(local.common_tags, { tier = var.environment == "prd" ? "prod" : "nonprod" })
}

resource "azurerm_role_assignment" "acrpull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = module.cluster.kubelet_identity_object_id
}

locals {
  # Cluster kube credentials — single source for the kubernetes/helm/kubectl providers (DRY).
  kube = {
    host        = module.cluster.host
    ca          = base64decode(module.cluster.cluster_ca_certificate)
    client_cert = base64decode(module.cluster.client_certificate)
    client_key  = base64decode(module.cluster.client_key)
  }

  # Common resource tags, framed from var.environment (no hardcoded env strings).
  common_tags = {
    platform    = "argocd"
    environment = var.environment
  }
}

# Foundational CRDs (Kubernetes Gateway API), installed by Terraform before the ingress stack.
# Pinned per cluster via var.gateway_api_version; promote sbx->prd by editing tfvars.
module "gateway_api_crds" {
  count  = var.enable_argocd ? 1 : 0
  source = "../../../../modules/gateway-api-crds"

  gateway_api_version = var.gateway_api_version
}

# GitOps stage: standalone Argo CD + root app. Enabled once the GitHub App creds are provided.
module "argocd" {
  count  = var.enable_argocd ? 1 : 0
  source = "../../../../modules/argocd-bootstrap"

  environment                = var.environment
  region                     = var.region
  cloud                      = "azure"
  argocd_chart_version       = var.argocd_chart_version
  platform_gitops_repo       = var.platform_gitops_repo
  platform_gitops_revision   = var.platform_gitops_revision
  github_org_url             = var.github_org_url
  github_app_id              = var.github_app_id
  github_app_installation_id = var.github_app_installation_id
  github_app_private_key     = var.github_app_private_key
  github_token               = var.github_token

  # Rancher ids (cluster-id + per-tenant '<clusterId>:<projectId>') onto the in-cluster cluster Secret,
  # so the tenants-namespace ApplicationSet can stamp field.cattle.io/projectId per namespace.
  cluster_secret_annotations = local.rancher_cluster_secret_annotations

  depends_on = [module.cluster, azurerm_role_assignment.acrpull, module.gateway_api_crds]
}

output "acr_login_server" { value = azurerm_container_registry.this.login_server }
output "resource_group" { value = module.cluster.resource_group_name }
output "cluster_name" { value = module.cluster.cluster_name }
