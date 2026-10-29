variable "subscription_id" { type = string }
variable "resource_group_name" { type = string }
variable "region" { type = string }
variable "cluster_name" { type = string }
variable "acr_name" { type = string }
variable "environment" {
  type    = string
  default = "sbx"
}
variable "node_count" {
  type    = number
  default = 3
}
variable "node_vm_size" {
  type    = string
  default = "Standard_D4ds_v6"
}

# Argo CD (GitOps stage)
variable "enable_argocd" {
  type    = bool
  default = false
}
variable "argocd_chart_version" {
  type        = string
  description = "argo-cd Helm chart version, pinned explicitly for this cluster (promote sbx->prd)."
}
variable "gateway_api_version" {
  type        = string
  description = "Gateway API bundle version (standard channel), pinned for this cluster (promote sbx->prd)."
}
variable "platform_gitops_repo" {
  type    = string
  default = "https://github.com/krupakar-hyland/platform-gitops"
}
variable "platform_gitops_revision" {
  type        = string
  description = "Git revision (branch/tag) Argo tracks for platform-gitops. Point at a branch for live testing before merging to main."
  default     = "main"
}
variable "github_org_url" {
  type    = string
  default = "https://github.com/krupakar-hyland"
}
variable "github_app_id" {
  type = string
}
variable "github_app_installation_id" {
  type = string
}
variable "github_app_private_key" {
  type      = string
  sensitive = true
}
variable "github_token" {
  type      = string
  default   = ""
  sensitive = true
}

# --- Rancher registration (per-cluster) -------------------------------------------------------
variable "enable_rancher_registration" {
  type        = bool
  description = "Register this cluster into Rancher and install the cattle-cluster-agent."
  default     = false
}

variable "rancher_url" {
  type        = string
  description = "Rancher API/UI URL (tools/rancher-cluster output)."
  default     = ""
}

variable "rancher_token" {
  type        = string
  description = "Rancher API token (tools/rancher-bootstrap output rancher_api_token)."
  default     = ""
  sensitive   = true
}

variable "rancher_insecure" {
  type    = bool
  default = true
}


variable "rancher_tenants" {
  type    = map(object({ group_principal_id = string }))
  default = {}
}
