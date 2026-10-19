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

# Argo CD (Phase 2)
variable "enable_argocd" {
  type    = bool
  default = false
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
