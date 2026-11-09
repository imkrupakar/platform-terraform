###############################################################################
# ingress.tf — AKS has NO built-in ingress controller, and Rancher needs a hostname.
# Create a STATIC public IP in the AKS node resource group (where the cluster identity already has
# rights), front it with ingress-nginx, and derive a Rancher hostname from its Azure DNS label
# (<label>.<region>.cloudapp.azure.com) so terraform apply yields a working Rancher URL, no external DNS.
###############################################################################

# Static public IP for the ingress LoadBalancer, with an Azure DNS label so Rancher gets a real
# *.cloudapp.azure.com FQDN. (sslip.io was reset by corporate SNI filtering; the Azure FQDN is not.)
resource "azurerm_public_ip" "ingress" {
  name                = "pip-${var.cluster_name}-ingress"
  resource_group_name = module.cluster.node_resource_group
  location            = var.region
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = var.dns_label
  tags                = { platform = "rancher-tools", environment = "tools" }
}

# Rancher hostname: explicit override, else the ingress IP's Azure FQDN (<label>.<region>.cloudapp.azure.com).
locals {
  rancher_hostname = var.rancher_hostname != "" ? var.rancher_hostname : azurerm_public_ip.ingress.fqdn
}

# ingress-nginx, pinned to the static IP (so Rancher's Ingress is actually served on AKS).
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_version
  namespace        = "ingress-nginx"
  create_namespace = true

  values = [yamlencode({
    controller = {
      replicaCount = var.ingress_nginx_replicas
      # Keep the long-lived Rancher agent WebSocket (remotedialer) open. nginx's 60s default read/send
      # timeout silently closes the idle tunnel, so the imported cluster flaps to "unavailable".
      config = {
        "proxy-read-timeout" = tostring(var.tunnel_proxy_timeout_seconds)
        "proxy-send-timeout" = tostring(var.tunnel_proxy_timeout_seconds)
      }
      service = {
        externalTrafficPolicy = "Local" # AKS probes the kube-proxy healthCheckNodePort (200 only where a pod runs) + preserves client source IP
        loadBalancerIP        = azurerm_public_ip.ingress.ip_address
        annotations = {
          "service.beta.kubernetes.io/azure-pip-name"                     = azurerm_public_ip.ingress.name
          "service.beta.kubernetes.io/azure-load-balancer-resource-group" = module.cluster.node_resource_group
          # Azure LB default 4m TCP idle timeout also cuts the agent tunnel; raise it (max 30).
          "service.beta.kubernetes.io/azure-load-balancer-tcp-idle-timeout" = tostring(var.lb_idle_timeout_minutes)
        }
      }
      # Rancher's own validating webhook + admission are enough; keep nginx lean for the POC.
      ingressClassResource = { default = true }
    }
  })]
}
