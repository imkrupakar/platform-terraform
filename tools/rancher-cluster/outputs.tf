output "rancher_url" {
  description = "Rancher API/UI URL — feed into tools/rancher-bootstrap as var.rancher_url."
  value       = "https://${local.rancher_hostname}"
}

output "rancher_hostname" {
  value = local.rancher_hostname
}

output "ingress_ip" {
  description = "Static public IP fronting ingress-nginx (the Azure FQDN resolves here)."
  value       = azurerm_public_ip.ingress.ip_address
}

output "cluster_name" {
  value = module.cluster.cluster_name
}

output "resource_group_name" {
  value = module.cluster.resource_group_name
}
