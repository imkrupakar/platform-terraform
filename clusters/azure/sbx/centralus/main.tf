# clusters/azure/sbx/centralus — provision the AKS cluster + ACR, then bootstrap Argo CD.
# Two-phase apply (first bring-up):
#   Phase 1 (cluster+ACR):  terraform apply -target=module.cluster -target=azurerm_container_registry.this -target=azurerm_role_assignment.acrpull
#   Phase 2 (argocd):       terraform apply            # after the GitHub App exists (set github_app_* vars)
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm    = { source = "hashicorp/azurerm", version = "~> 4.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
    helm       = { source = "hashicorp/helm", version = "~> 2.13" }
    kubectl    = { source = "gavinbunney/kubectl", version = "~> 1.14" }
    http       = { source = "hashicorp/http", version = "~> 3.4" }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

module "cluster" {
  source              = "../../../../modules/aks-cluster"
  name                = var.cluster_name
  region              = var.region
  resource_group_name = var.resource_group_name
  node_count          = var.node_count
  node_vm_size        = var.node_vm_size
  tags                = { platform = "argocd-sandbox", environment = var.environment }
}

# Nonprod ACR in the same platform RG; AKS kubelet identity gets AcrPull.
resource "azurerm_container_registry" "this" {
  name                = var.acr_name
  resource_group_name = module.cluster.resource_group_name
  location            = var.region
  sku                 = "Standard"
  admin_enabled       = false
  tags                = { platform = "argocd-sandbox", tier = "nonprod" }
}

resource "azurerm_role_assignment" "acrpull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = module.cluster.kubelet_identity_object_id
}

# --- Providers configured against the freshly created cluster (used in Phase 2) ---
provider "kubernetes" {
  host                   = module.cluster.host
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
  client_certificate     = base64decode(module.cluster.client_certificate)
  client_key             = base64decode(module.cluster.client_key)
}

provider "helm" {
  kubernetes {
    host                   = module.cluster.host
    cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
    client_certificate     = base64decode(module.cluster.client_certificate)
    client_key             = base64decode(module.cluster.client_key)
  }
}

provider "kubectl" {
  host                   = module.cluster.host
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
  client_certificate     = base64decode(module.cluster.client_certificate)
  client_key             = base64decode(module.cluster.client_key)
  load_config_file       = false
}

# Phase 2: standalone Argo CD + root app. Enabled once the GitHub App creds are provided.
module "argocd" {
  count  = var.enable_argocd ? 1 : 0
  source = "../../../../modules/argocd-bootstrap"

  environment                = var.environment
  region                     = var.region
  cloud                      = "azure"
  argocd_chart_version       = var.argocd_chart_version
  gateway_api_version        = var.gateway_api_version
  platform_gitops_repo       = var.platform_gitops_repo
  github_org_url             = var.github_org_url
  github_app_id              = var.github_app_id
  github_app_installation_id = var.github_app_installation_id
  github_app_private_key     = var.github_app_private_key
  github_token               = var.github_token

  depends_on = [module.cluster, azurerm_role_assignment.acrpull]
}

output "acr_login_server" { value = azurerm_container_registry.this.login_server }
output "resource_group" { value = module.cluster.resource_group_name }
output "cluster_name" { value = module.cluster.cluster_name }
