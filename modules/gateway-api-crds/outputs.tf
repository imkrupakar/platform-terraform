output "gateway_api_version" {
  description = "The Gateway API bundle version installed on this cluster."
  value       = var.gateway_api_version
}

output "channel" {
  description = "The Gateway API release channel installed."
  value       = var.channel
}
