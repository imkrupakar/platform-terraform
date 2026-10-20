###############################################################################
# gateway-api-crds — install the Kubernetes Gateway API CRDs (foundation).
#
# A cluster capability (like the Argo CD install), installed by Terraform rather than GitOps:
#   - it must exist before the ingress stack (istiod reconciling Gateways, the platform Gateway,
#     and any team HTTPRoute);
#   - managing it here avoids GitOps prune cascades — deleting these CRDs would delete every
#     Gateway/HTTPRoute cluster-wide.
# The bundle is pinned by `gateway_api_version` and promoted sbx->prd via each cluster's tfvars.
# Server-side apply is required (the bundle exceeds the client-side apply size limit); istiod and the
# platform Gateway (both GitOps) retry until these CRDs exist.
#
# Providers (kubectl against the target cluster, http) are configured by the caller.
###############################################################################

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    kubectl = { source = "gavinbunney/kubectl", version = "~> 1.14" }
    http    = { source = "hashicorp/http", version = "~> 3.4" }
  }
}

data "http" "bundle" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v${var.gateway_api_version}/${var.channel}-install.yaml"
}

data "kubectl_file_documents" "bundle" {
  content = data.http.bundle.response_body
}

resource "kubectl_manifest" "gateway_api_crds" {
  for_each          = data.kubectl_file_documents.bundle.manifests
  yaml_body         = each.value
  server_side_apply = true
  # force_conflicts adopts field ownership from any prior manager (e.g. Argo's argocd-controller
  # during the one-time migration from GitOps to Terraform).
  force_conflicts = true
  wait            = true
}
