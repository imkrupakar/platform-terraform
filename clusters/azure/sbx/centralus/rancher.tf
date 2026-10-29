# Register THIS cluster into Rancher (decentralised, per-cluster model — the cluster registers
# itself, like it already self-bootstraps Argo CD). Gated OFF by default so a normal apply is
# unaffected; set enable_rancher_registration=true with rancher_url + rancher_token to join.
#
# The agent (cattle-cluster-agent) is installed by the module applying Rancher's registration
# manifest to this cluster; it then dials OUT to Rancher.
provider "rancher2" {
  api_url   = var.rancher_url
  token_key = var.rancher_token
  insecure  = var.rancher_insecure
}

module "rancher_register" {
  count  = var.enable_rancher_registration ? 1 : 0
  source = "../../../../modules/rancher-register"

  # Rancher cluster name = the cloud-provisioned cluster name (no separate var needed).
  cluster_name = module.cluster.cluster_name

  # Creds for THIS cluster, so the module applies the registration manifest without an ambient
  # kube-context (CI-safe). Sourced from the same module.cluster outputs the providers use.
  cluster_host           = module.cluster.host
  cluster_ca_certificate = module.cluster.cluster_ca_certificate
  client_certificate     = module.cluster.client_certificate
  client_key             = module.cluster.client_key

  tenants = var.rancher_tenants
}

output "rancher_tenant_project_ids" {
  description = "Per-tenant '<clusterId>:<projectId>' for the namespace projectId mapping."
  value       = var.enable_rancher_registration ? module.rancher_register[0].tenant_project_ids : {}
}

# Rancher ids stamped onto the Argo in-cluster cluster Secret (read by the tenants-namespace
# ApplicationSet to map each namespace -> its Rancher Project). cluster-id is informational; the
# per-team value is the full '<clusterId>:<projectId>' used verbatim as field.cattle.io/projectId.
locals {
  rancher_cluster_secret_annotations = var.enable_rancher_registration ? merge(
    { "rancher.platform.internal/cluster-id" = module.rancher_register[0].cluster_id },
    { for team, projectid in module.rancher_register[0].tenant_project_ids :
      "rancher.platform.internal/project-${team}" => projectid
    }
  ) : {}
}
