###############################################################################
# aks-cluster — real AKS cluster for the sandbox: Resource Group + VNet/subnet + AKS
# (Azure CNI overlay, OIDC issuer + workload identity, system-assigned identity).
# Outputs feed the kubernetes/helm/kubectl providers and AcrPull wiring in the stack.
###############################################################################
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}

variable "name" { type = string }
variable "region" { type = string }
variable "resource_group_name" { type = string }

variable "kubernetes_version" {
  type    = string
  default = null # null => AKS default for the region
}
variable "node_count" {
  type    = number
  default = 3
}
variable "node_vm_size" {
  type    = string
  default = "Standard_D4ds_v6"
}
variable "vnet_cidr" {
  type    = string
  default = "10.60.0.0/16"
}
variable "node_subnet_cidr" {
  type    = string
  default = "10.60.0.0/22"
}
variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.region
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "snet-nodes"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.node_subnet_cidr]
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version

  # OIDC issuer + workload identity (no static secrets for add-ons/apps later).
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name           = "system"
    node_count     = var.node_count
    vm_size        = var.node_vm_size
    vnet_subnet_id = azurerm_subnet.nodes.id
    os_sku         = "AzureLinux"
    upgrade_settings {
      max_surge = "10%" # match the AKS default so plans stay clean
    }
  }

  identity { type = "SystemAssigned" }

  # Azure CNI overlay: scalable pod networking without burning VNet IPs per pod.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    network_data_plane  = "cilium"
    load_balancer_sku   = "standard"
  }

  tags = var.tags
}

output "cluster_name" { value = azurerm_kubernetes_cluster.this.name }
output "resource_group_name" { value = azurerm_resource_group.this.name }
output "node_resource_group" { value = azurerm_kubernetes_cluster.this.node_resource_group }

output "host" {
  value = azurerm_kubernetes_cluster.this.kube_config[0].host
}
output "cluster_ca_certificate" {
  value = azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
}
output "client_certificate" {
  value = azurerm_kubernetes_cluster.this.kube_config[0].client_certificate
}
output "client_key" {
  value = azurerm_kubernetes_cluster.this.kube_config[0].client_key
}

# Kubelet managed identity — grant it AcrPull on the ACR (done in the stack).
output "kubelet_identity_object_id" {
  value = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}
