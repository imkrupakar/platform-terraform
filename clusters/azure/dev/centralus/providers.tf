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

# kubernetes/helm/kubectl target the freshly created cluster via local.kube (defined in main.tf).
provider "kubernetes" {
  host                   = local.kube.host
  cluster_ca_certificate = local.kube.ca
  client_certificate     = local.kube.client_cert
  client_key             = local.kube.client_key
}

provider "helm" {
  kubernetes {
    host                   = local.kube.host
    cluster_ca_certificate = local.kube.ca
    client_certificate     = local.kube.client_cert
    client_key             = local.kube.client_key
  }
}

provider "kubectl" {
  host                   = local.kube.host
  cluster_ca_certificate = local.kube.ca
  client_certificate     = local.kube.client_cert
  client_key             = local.kube.client_key
  load_config_file       = false
}
