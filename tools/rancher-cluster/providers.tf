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

# Talk to the freshly created tools cluster via its admin kube_config.
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
