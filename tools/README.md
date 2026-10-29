# tools/ — Rancher on a dedicated tools cluster (Terraform)

Stands up the **Rancher** access-management plane and wires it to our GitOps tenancy model.
Design: [`ArgoCDPlatform/docs/rancher-access-strategy.md`](../../../ArgoCDPlatform/docs/rancher-access-strategy.md).

```
platform-terraform/
├── tools/
│   ├── rancher-cluster/     STACK 1 — AKS tools cluster + cert-manager + ingress-nginx + Rancher
│   └── rancher-bootstrap/   one-time — set admin password, mint API token, (optional) GitHub auth
└── modules/
    └── rancher-register/    per-cluster — a fleet cluster registers ITSELF + installs its agent
```

**Registration is decentralised:** each fleet cluster registers itself by calling
`modules/rancher-register` from its own stack (the same pattern by which each cluster self-bootstraps
Argo CD). No central stack imports the fleet.

## 1. STACK 1 — tools cluster + add-ons
```shell
cd rancher-cluster
cp terraform.tfvars.example terraform.tfvars   # set rancher_bootstrap_password (hostname optional)
terraform init && terraform apply
terraform output rancher_url                    # https://<dns_label>.<region>.cloudapp.azure.com
```
Installs on the tools cluster: `cert-manager`, **`ingress-nginx`** (with a **static public IP** in the
AKS node RG), and **Rancher** (`cattle-system`, self-signed TLS). The Rancher hostname is the ingress
IP's **Azure FQDN** (`<dns_label>.<region>.cloudapp.azure.com`), so no external DNS is needed.

> AKS has no built-in ingress controller and Rancher needs a hostname — hence the ingress-nginx +
> static IP + Azure DNS label. (sslip.io/nip.io were reset by corporate SNI filtering; the Azure
> `*.cloudapp.azure.com` FQDN is not filtered.) This stack provisions the tools cluster
> (`platform-tools-cus` in `rg-platform-tools-cus-01`) **from scratch** — the earlier `az aks create`
> cluster was deleted and replaced by this declarative definition (no `terraform import` needed).

## 2. rancher-bootstrap — admin token (run once)
```shell
cd ../rancher-bootstrap
cp terraform.tfvars.example terraform.tfvars   # rancher_url (STACK 1), bootstrap + admin passwords
terraform init && terraform apply
terraform output -raw rancher_api_token         # feed to each fleet cluster stack as rancher_token
```
Optional: set `enable_github_auth=true` + the GitHub OAuth App creds to turn on GitHub login.

## 3. Register a fleet cluster (installs the agent) — from the cluster's OWN stack
Each cluster stack calls `modules/rancher-register` (already wired into
`clusters/azure/sbx/centralus` behind `enable_rancher_registration`). Register `aks-sbx-cus`:
```shell
cd ../../clusters/azure/sbx/centralus
terraform apply \
  -var enable_rancher_registration=true \
  -var rancher_url="https://<dns_label>.<region>.cloudapp.azure.com" \
  -var rancher_token="<rancher_api_token>"
```
This creates the imported `rancher2_cluster` (named after the cloud-provisioned cluster) and applies its registration manifest to the cluster →
installs **cattle-cluster-agent** (+ fleet-agent). The apply needs no local kube-context — the module
builds a throwaway kubeconfig from the cluster's own creds (`module.cluster` outputs), so it runs the
same from CI (GitHub Actions / Spacelift); the runner just needs `kubectl` + `curl` on PATH. Verify:
```shell
kubectl -n cattle-system get deploy cattle-cluster-agent   # against the registered cluster's context
# and the cluster shows Active in the Rancher UI
```
Set `rancher_enable_tenant_projects=true` + `rancher_tenants` (once GitHub auth is on) to also create
per-tenant Rancher Projects; `terraform output rancher_tenant_project_ids` then feeds the namespace
`field.cattle.io/projectId` map (strategy §5-A).

## Notes
- **POC scope:** 1 Rancher replica, self-signed TLS, no HA/backup. Prod: replicas=3, real cert.
- **Rancher ↔ k8s matrix:** `kubernetes_version` (1.34) and `rancher_version` (2.15.2, latest) must be compatible —
  verify against the Rancher release and bump together if needed.
- **Token distribution:** each cluster stack needs the Rancher URL + token. Use a scoped token from a
  secret manager / `TF_VAR_rancher_token`; never commit it.
