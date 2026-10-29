variable "subscription_id" {
  type        = string
  description = "Azure subscription that hosts the tools cluster."
  default     = "c556d760-610e-4ac0-a522-dc67de95d763" # CIC - Nucleus Cloud Platform - Internal Sandbox - CentralUS
}

variable "region" {
  type    = string
  default = "centralus"
}

variable "resource_group_name" {
  type    = string
  default = "rg-platform-tools-cus-01"
}

variable "cluster_name" {
  type    = string
  default = "platform-tools-cus"
}

variable "kubernetes_version" {
  type        = string
  description = "Pin a Rancher-supported Kubernetes version for the local cluster."
  default     = "1.34"
}

variable "node_count" {
  type        = number
  description = "Tools cluster node count. HA Rancher (3 replicas) wants 3 nodes so replicas spread one-per-node."
  default     = 3
}

variable "node_vm_size" {
  type    = string
  default = "Standard_D4ds_v6"
}

variable "cert_manager_version" {
  type        = string
  description = "cert-manager chart version (keep compatible with the chosen Rancher version)."
  default     = "v1.21.3"
}

variable "rancher_version" {
  type        = string
  description = "Rancher server chart version (latest stable). Must support kubernetes_version (2.15.x supports k8s 1.34)."
  default     = "2.15.2"
}

variable "rancher_hostname" {
  type        = string
  description = "Override the Rancher ingress hostname. Empty => the ingress IP's Azure FQDN (<dns_label>.<region>.cloudapp.azure.com)."
  default     = ""
}

variable "dns_label" {
  type        = string
  description = "Azure DNS label for the ingress public IP; yields <label>.<region>.cloudapp.azure.com (avoids SNI-filtered sslip.io/nip.io)."
  default     = "rancher-platform-tools-cus"
}

variable "ingress_nginx_version" {
  type        = string
  description = "ingress-nginx chart version."
  default     = "4.15.1"
}

variable "rancher_bootstrap_password" {
  type        = string
  description = "Initial bootstrap password for the Rancher admin user (consumed by STACK 2's rancher2_bootstrap)."
  sensitive   = true
}

# --- HA / tunnel stability -------------------------------------------------------------------
variable "rancher_replicas" {
  type        = number
  description = "Rancher server replicas. 3 = HA (needs >=3 nodes for one-per-node spread)."
  default     = 3
}

variable "ingress_nginx_replicas" {
  type        = number
  description = "ingress-nginx controller replicas (HA front door for the Rancher agent tunnel)."
  default     = 2
}

variable "tunnel_proxy_timeout_seconds" {
  type        = number
  description = "nginx proxy read/send timeout for the long-lived Rancher agent WebSocket (remotedialer). The 60s default silently drops the tunnel -> cluster flaps to unavailable."
  default     = 3600
}

variable "lb_idle_timeout_minutes" {
  type        = number
  description = "Azure LB TCP idle timeout for the ingress public IP (4m default also cuts the agent tunnel). Max 30."
  default     = 30
}
