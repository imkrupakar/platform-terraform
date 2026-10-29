variable "cluster_name" {
  type        = string
  description = "Name this cluster should have in Rancher (e.g. sbx-azure-centralus)."
}

# --- Credentials for THIS cluster, used only to apply the registration manifest (CI-safe; no
#     ambient kube-context). Pass the caller's `module.cluster` outputs. The *_certificate / key
#     values are base64-encoded (as AKS/EKS emit them) and consumed verbatim as kubeconfig *-data. ---
variable "cluster_host" {
  type        = string
  description = "Kubernetes API server URL for THIS cluster (module.cluster.host)."
}

variable "cluster_ca_certificate" {
  type        = string
  description = "base64 cluster CA certificate for THIS cluster (module.cluster.cluster_ca_certificate)."
  sensitive   = true
}

variable "client_certificate" {
  type        = string
  description = "base64 client certificate for THIS cluster (module.cluster.client_certificate)."
  sensitive   = true
}

variable "client_key" {
  type        = string
  description = "base64 client key for THIS cluster (module.cluster.client_key)."
  sensitive   = true
}

variable "tenants" {
  description = "Tenants => GitHub-team group principal (github_team://<id>). One Rancher Project (1:1) named per tenant + a project-member binding. Empty map => no Projects."
  type        = map(object({ group_principal_id = string }))
  default     = {}
}
