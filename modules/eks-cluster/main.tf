###############################################################################
# eks-cluster — real EKS cluster for the sandbox: VPC (3-AZ public/private, single NAT)
# + EKS control plane (IRSA/OIDC) + one managed node group. A thin WRAPPER around the
# de-facto-standard terraform-aws-modules so every cluster stack stays DRY and pins versions
# in one place (mirrors modules/aks-cluster). Outputs feed the kubernetes/helm/kubectl providers.
###############################################################################
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
}

variable "name" { type = string }               # cluster name, e.g. eks-sbx-use2
variable "region" { type = string }             # e.g. us-east-2
variable "kubernetes_version" { type = string } # e.g. "1.31"
variable "node_count" {
  type    = number
  default = 3
}
variable "node_instance_type" {
  type    = string
  default = "m6i.xlarge" # 4 vCPU / 16 GiB, the EC2 analogue of AKS Standard_D4ds_v6
}
variable "vpc_cidr" {
  type    = string
  default = "10.61.0.0/16" # non-overlapping with the AKS VNet (10.60.0.0/16)
}
variable "tags" {
  type    = map(string)
  default = {}
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Three AZs; /20 private + /24 public subnets carved from the VPC CIDR.
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 4, i)]      # 10.61.0/20, 16/20, 32/20
  public_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i + 48)] # 10.61.48/24, 49/24, 50/24
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "vpc-${var.name}"
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true # one NAT for the whole sandbox VPC (cost)
  enable_dns_hostnames = true

  # Subnet tags required by the AWS Load Balancer Controller / EKS for subnet discovery.
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }

  tags = var.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.name
  cluster_version = var.kubernetes_version

  # Public endpoint so the Terraform runner (and kubectl) can reach the API in the sandbox.
  cluster_endpoint_public_access = true

  # The IAM principal running Terraform becomes a cluster admin (EKS access entries), so the
  # kubernetes/helm/kubectl providers can apply the Argo CD bootstrap.
  enable_cluster_creator_admin_permissions = true

  # IRSA (OIDC provider) so add-ons/apps authenticate to AWS without static keys.
  enable_irsa = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    system = {
      instance_types = [var.node_instance_type]
      min_size       = var.node_count
      max_size       = var.node_count
      desired_size   = var.node_count
      # The default EKS node role includes AmazonEC2ContainerRegistryReadOnly (ECR pull).
    }
  }

  tags = var.tags
}

output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "cluster_ca_certificate" { value = module.eks.cluster_certificate_authority_data }
output "oidc_provider_arn" { value = module.eks.oidc_provider_arn }
output "node_security_group_id" { value = module.eks.node_security_group_id }
output "vpc_id" { value = module.vpc.vpc_id }
output "private_subnet_ids" { value = module.vpc.private_subnets }
