variable "gateway_api_version" {
  type        = string
  description = "Gateway API bundle version (without the leading v), e.g. 1.6.3. Pinned per cluster; promote sbx->prd."
}

variable "channel" {
  type        = string
  description = "Gateway API release channel: standard (GA/beta) or experimental (adds TCP/TLS/UDPRoute)."
  default     = "standard"

  validation {
    condition     = contains(["standard", "experimental"], var.channel)
    error_message = "channel must be \"standard\" or \"experimental\"."
  }
}
