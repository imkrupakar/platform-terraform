###############################################################################
# argocd-bootstrap — install Argo CD on THIS cluster and hand control to GitOps.
# Consumed by each clusters/<cluster> stack. Providers (kubernetes, helm) are configured
# by the caller against the freshly created cluster. required_providers lives in providers.tf.
###############################################################################

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

  wait            = true
  timeout         = 900
  atomic          = false # keep a partial install for debugging instead of uninstalling
  cleanup_on_fail = false
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
    annotations = var.cluster_secret_annotations
  }
  data = {
    name   = "in-cluster"
    server = "https://kubernetes.default.svc"
    config = jsonencode({ tlsClientConfig = { insecure = false } })
  }
  depends_on = [helm_release.argocd]
}

# 3. The single bootstrap secret — repo-creds for private Git read access.
#    Production: GitHub App (githubApp* fields). Sandbox: a token (username/password) when
#    var.github_token is set — lets the first bring-up proceed without the GitHub App browser flow.
locals {
  use_token = var.github_token != ""
}

resource "kubernetes_secret" "github_app_creds" {
  count = local.use_token ? 0 : 1
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

resource "kubernetes_secret" "github_token_creds" {
  count = local.use_token ? 1 : 0
  metadata {
    name      = "github-token-creds"
    namespace = "argocd"
    labels    = { "argocd.argoproj.io/secret-type" = "repo-creds" }
  }
  data = {
    type     = "git"
    url      = var.github_org_url
    username = "x-access-token"
    password = var.github_token
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
    kubernetes_secret.github_token_creds,
  ]
}
