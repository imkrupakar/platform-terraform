# clusters/aws/sbx/us-east-2 — provision the EKS cluster + VPC + ECR, then bootstrap Argo CD.
# Mirrors clusters/azure/sbx/centralus. Single `terraform apply` provisions everything in one pass.
# First bring-up of a brand-new cluster: apply once with enable_argocd=false to stand up infra,
# create the GitHub App, then apply with enable_argocd=true and the github_app_* vars set.
# Provider + required_providers config lives in providers.tf.

module "eks" {
  source = "../../../../modules/eks-cluster"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  node_count         = var.node_count
  node_instance_type = var.node_instance_type
  tags               = local.common_tags
}

locals {
  # Common resource tags, framed from var.environment (no hardcoded env strings).
  common_tags = {
    platform    = "argocd"
    environment = var.environment
  }
}

# ECR has no "registry" resource (unlike ACR) — the registry is implicit per account+region.
# Each repository is its own resource; node pull is via the EKS node role's ECR-read policy.
resource "aws_ecr_repository" "this" {
  for_each             = toset(var.ecr_repositories)
  name                 = each.value
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # sandbox: allow terraform destroy even with images present
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = merge(local.common_tags, { tier = var.environment == "prd" ? "prod" : "nonprod" })
}

# Foundational CRDs (Kubernetes Gateway API), installed by Terraform before the ingress stack.
module "gateway_api_crds" {
  count  = var.enable_argocd ? 1 : 0
  source = "../../../../modules/gateway-api-crds"

  gateway_api_version = var.gateway_api_version
}

# GitOps stage: standalone Argo CD + root app. Enabled once the GitHub App creds are provided.
module "argocd" {
  count  = var.enable_argocd ? 1 : 0
  source = "../../../../modules/argocd-bootstrap"

  environment                = var.environment
  region                     = var.region
  cloud                      = "aws"
  argocd_chart_version       = var.argocd_chart_version
  platform_gitops_repo       = var.platform_gitops_repo
  github_org_url             = var.github_org_url
  github_app_id              = var.github_app_id
  github_app_installation_id = var.github_app_installation_id
  github_app_private_key     = var.github_app_private_key
  github_token               = var.github_token

  depends_on = [module.eks, module.gateway_api_crds]
}

output "ecr_repository_urls" { value = { for k, r in aws_ecr_repository.this : k => r.repository_url } }
output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
