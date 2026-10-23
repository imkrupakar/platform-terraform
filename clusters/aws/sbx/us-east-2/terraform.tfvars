region             = "us-east-1"
cluster_name       = "eks-sbx-use1"
kubernetes_version = "1.34"
environment        = "sbx"
node_count         = 2
node_instance_type = "m6i.xlarge"
ecr_repositories   = ["orders-api"]

enable_argocd        = true
argocd_chart_version = "10.10.1"
gateway_api_version  = "1.6.3"

# Same org-wide GitHub App as the AKS cluster (reused for Argo CD repo-creds).
github_app_id              = "5379839"
github_app_installation_id = "172998649"
# github_app_private_key supplied via TF_VAR_github_app_private_key="$(cat argocd-app.pem)"
