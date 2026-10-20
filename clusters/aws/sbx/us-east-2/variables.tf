variable "region" { type = string }
variable "cluster_name" { type = string }

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}
variable "environment" {
  type    = string
  default = "sbx"
}
variable "node_count" {
  type    = number
  default = 3
}
variable "node_instance_type" {
  type    = string
  default = "m6i.xlarge"
}
variable "ecr_repositories" {
  type        = list(string)
  description = "ECR repositories to create in this account/region (the ACR-repositories analogue)."
  default     = ["orders-api"]
}

# Argo CD (Phase 2)
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
variable "github_org_url" {
  type    = string
  default = "https://github.com/krupakar-hyland"
}
variable "github_app_id" {
  type    = string
  default = ""
}
variable "github_app_installation_id" {
  type    = string
  default = ""
}
variable "github_app_private_key" {
  type      = string
  default   = ""
  sensitive = true
}
variable "github_token" {
  type      = string
  default   = ""
  sensitive = true
}
