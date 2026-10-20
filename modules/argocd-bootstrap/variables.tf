variable "environment" {
  type        = string
  description = "sbx | dev | stg | prd"
}

variable "region" {
  type = string
}

variable "cloud" {
  type        = string
  description = "azure | aws"
}

variable "argocd_chart_version" {
  type        = string
  description = "argo-cd Helm chart version (argoproj/argo-helm). Pinned explicitly per cluster; promote sbx->prd."
}

variable "platform_gitops_repo" {
  type    = string
  default = "https://github.com/krupakar-hyland/platform-gitops"
}

variable "platform_gitops_revision" {
  type    = string
  default = "main"
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

# Sandbox alternative to the GitHub App: a token used as repo-creds (username x-access-token).
# When set, the GitHub App secret is skipped. Leave empty to use the GitHub App.
variable "github_token" {
  type      = string
  default   = ""
  sensitive = true
}
