###############################################################################
# argocd-bootstrap — install Argo CD on THIS cluster and hand control to GitOps.
# Consumed by each clusters/<cluster> stack. Providers (kubernetes, helm) are configured
# by the caller against the freshly created cluster.
###############################################################################

terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
    helm       = { source = "hashicorp/helm", version = "~> 2.13" }
    kubectl    = { source = "gavinbunney/kubectl", version = "~> 1.14" }
  }
}

locals {
  # Prod clusters get an HA Argo CD; nonprod a single-replica install.
  is_prod   = var.environment == "prd"
  ha_values = local.is_prod ? [file("${path.module}/values/argocd-ha.yaml")] : []
}

# 1. Install Argo CD (standalone, one per cluster).
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version

  values = concat([file("${path.module}/values/argocd.yaml")], local.ha_values)

  atomic          = true
  cleanup_on_fail = true
}

# 2. Label the in-cluster so the platform ApplicationSets (cluster generator) can read
#    this cluster's identity. This is what makes the SAME GitOps config render the right
#    environment on every standalone cluster.
resource "kubernetes_secret" "in_cluster" {
  metadata {
    name      = "in-cluster"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      environment                      = var.environment
      region                           = var.region
      cloud                            = var.cloud
      workloads                        = "true"
    }
  }
  data = {
    name   = "in-cluster"
    server = "https://kubernetes.default.svc"
    config = jsonencode({ tlsClientConfig = { insecure = false } })
  }
  depends_on = [helm_release.argocd]
}

# 3. The single bootstrap secret — GitHub App repo-creds (private Git read access).
#    ESO later uses workload identity, so this is the only secret Terraform seeds.
resource "kubernetes_secret" "github_app_creds" {
  metadata {
    name      = "github-app-creds"
    namespace = "argocd"
    labels    = { "argocd.argoproj.io/secret-type" = "repo-creds" }
  }
  data = {
    type                    = "git"
    url                     = var.github_org_url
    githubAppID             = var.github_app_id
    githubAppInstallationID = var.github_app_installation_id
    githubAppPrivateKey     = var.github_app_private_key
  }
  depends_on = [helm_release.argocd]
}

# 4. Apply the ONE root Application (app-of-apps). Argo CD self-manages from here.
#    Uses kubectl_manifest (not kubernetes_manifest): kubernetes_manifest needs the
#    Application CRD to already exist AT PLAN TIME, but that CRD is installed by the
#    helm_release above in the SAME apply — so kubernetes_manifest fails on first apply.
#    kubectl_manifest applies server-side without a plan-time schema lookup.
resource "kubectl_manifest" "root_app" {
  server_side_apply = true
  wait              = true

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "platform-root"
      namespace  = "argocd"
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.platform_gitops_repo
        targetRevision = var.platform_gitops_revision
        path           = "bootstrap/app-of-apps"
        directory      = { recurse = true }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated   = { prune = true, selfHeal = true }
        syncOptions = ["ServerSideApply=true", "CreateNamespace=false"]
      }
    }
  })

  depends_on = [
    helm_release.argocd,
    kubernetes_secret.in_cluster,
    kubernetes_secret.github_app_creds,
  ]
}
