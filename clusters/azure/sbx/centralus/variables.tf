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
  default = "https://github.com/imkrupakar/platform-gitops"
}
variable "platform_gitops_revision" {
  type        = string
  description = "Git revision (branch/tag) Argo tracks for platform-gitops. Point at a branch for live testing before merging to main."
  default     = "main"
}
variable "github_org_url" {
  type    = string
  default = "https://github.com/imkrupakar"
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
# Presence of this object enables registration (omit it to skip). `url` is required; the token is a
# separate sensitive var (Terraform forbids sensitive values in count/for_each, and it keeps the
# secret injectable via TF_VAR_rancher_token).
variable "rancher" {
  type = object({
    url      = string
    insecure = optional(bool, true)
  })
  description = "Rancher connection for this cluster (tools/rancher-cluster output). Omit to skip registration."
  default     = null
}

variable "rancher_token" {
  type        = string
  description = "Rancher API token (tools/rancher-bootstrap output). Required when `rancher` is set; supply via TF_VAR_rancher_token / a secret manager."
  default     = ""
  sensitive   = true

  # Fail fast at plan time instead of an opaque rancher2 provider auth error.
  validation {
    condition     = var.rancher == null || var.rancher_token != ""
    error_message = "rancher_token is required when `rancher` is set (export TF_VAR_rancher_token)."
  }
}

variable "tenants" {
  type        = map(object({ group_principal_id = string }))
  description = "1:1 tenant=Rancher Project. tenant => { group_principal_id } (GitHub team). Empty principal => Project only (no RBAC binding)."
  default     = {}
}
