variable "rancher_url" {
  type        = string
  description = "Rancher API/UI URL (tools/rancher-cluster output rancher_url)."
}

variable "rancher_insecure" {
  type        = bool
  description = "POC: trust Rancher's self-signed cert."
  default     = true
}

variable "rancher_bootstrap_password" {
  type        = string
  description = "Bootstrap password set in tools/rancher-cluster (helm bootstrapPassword)."
  sensitive   = true
}

variable "rancher_admin_password" {
  type        = string
  description = "New admin password to set on first login."
  sensitive   = true
}

variable "enable_github_auth" {
  type        = bool
  description = "Enable GitHub auth (needs a GitHub OAuth App). Deferred by default."
  default     = false
}

variable "github_client_id" {
  type    = string
  default = ""
}

variable "github_client_secret" {
  type      = string
  default   = ""
  sensitive = true
}
