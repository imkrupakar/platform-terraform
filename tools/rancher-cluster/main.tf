###############################################################################
# tools/rancher-cluster — STACK 1
# Provision the dedicated "tools" cluster (Rancher's local cluster) and install the add-ons
# Rancher needs: cert-manager + the Rancher server (Helm). Outputs rancher_url for STACK 2.
#
# Apply order:  this stack  ->  tools/rancher-config (rancher2: auth, imported clusters, projects)
###############################################################################
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm    = { source = "hashicorp/azurerm", version = "~> 4.0" }
    helm       = { source = "hashicorp/helm", version = "~> 2.13" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

# RG + VNet + AKS (system-assigned identity, OIDC issuer + workload identity). Same module the
# workload clusters use — a tools cluster is just an AKS cluster with no ACR/Argo wiring.
module "cluster" {
  source              = "../../modules/aks-cluster"
  name                = var.cluster_name
  region              = var.region
  resource_group_name = var.resource_group_name
  kubernetes_version  = var.kubernetes_version
  node_count          = var.node_count
  node_vm_size        = var.node_vm_size
  tags                = { platform = "rancher-tools", environment = "tools" }
}

# Providers talk to the freshly created tools cluster via its admin kube_config.
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

# --- Add-on 1: cert-manager (Rancher's one prerequisite; issues the Rancher ingress cert) -------
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_version
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "crds.enabled"
    value = "true"
  }
}

# --- Add-on 2: Rancher server (management plane + UI/API) ----------------------------------------
# HA: var.rancher_replicas (default 3). TLS is Rancher-generated self-signed; for real use swap to
# Let's Encrypt/BYO cert. 3 replicas need >=3 nodes so the chart's pod anti-affinity spreads them.
resource "helm_release" "rancher" {
  name             = "rancher"
  repository       = "https://releases.rancher.com/server-charts/latest"
  chart            = "rancher"
  version          = var.rancher_version
  namespace        = "cattle-system"
  create_namespace = true
  depends_on       = [helm_release.cert_manager, helm_release.ingress_nginx]

  set {
    name  = "hostname"
    value = local.rancher_hostname
  }
  set {
    name  = "ingressClassName"
    value = "nginx"
  }
  set {
    name  = "replicas"
    value = tostring(var.rancher_replicas)
  }
  set {
    name  = "bootstrapPassword"
    value = var.rancher_bootstrap_password
  }
  # Rancher-generated self-signed CA (default). cert-manager manages the cert.
  set {
    name  = "ingress.tls.source"
    value = "rancher"
  }
  # POC convenience: let a new agent trust the self-signed CA without strict pinning.
  set {
    name  = "agentTLSMode"
    value = "system-store"
  }
}
