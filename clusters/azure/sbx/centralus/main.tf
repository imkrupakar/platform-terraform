# clusters/azure/sbx/centralus — provision the AKS cluster + ACR, then bootstrap Argo CD.
# Single `terraform apply` provisions everything (cluster, Gateway API CRDs, Argo CD) in one pass.
# First bring-up of a brand-new cluster: apply once with enable_argocd=false to stand up infra,
# create the GitHub App, then apply with enable_argocd=true and the github_app_* vars set.
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

# --- Providers configured against the freshly created cluster (used by the GitOps stage) ---
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
  github_org_url             = var.github_org_url
  github_app_id              = var.github_app_id
  github_app_installation_id = var.github_app_installation_id
  github_app_private_key     = var.github_app_private_key
  github_token               = var.github_token

  depends_on = [module.cluster, azurerm_role_assignment.acrpull, module.gateway_api_crds]
}

output "acr_login_server" { value = azurerm_container_registry.this.login_server }
output "resource_group" { value = module.cluster.resource_group_name }
output "cluster_name" { value = module.cluster.cluster_name }
