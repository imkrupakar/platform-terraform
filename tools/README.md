# tools/ — Rancher on a dedicated tools cluster (Terraform)

Stands up the **Rancher** access-management plane that fleet clusters register into.

```
platform-terraform/
├── tools/
│   ├── rancher-cluster/     STACK 1 — AKS tools cluster + cert-manager + ingress-nginx + Rancher
│   └── rancher-bootstrap/   one-time — set admin password, mint API token, (optional) GitHub auth
└── modules/
    └── rancher-register/    per-cluster — a fleet cluster registers ITSELF + installs its agent
```

Registration is decentralised: each fleet cluster registers itself by calling
`modules/rancher-register` from its own stack. No central stack imports the fleet.

## 1. Tools cluster + add-ons
```shell
cd rancher-cluster
cp terraform.tfvars.example terraform.tfvars   # set rancher_bootstrap_password (hostname optional)
terraform init && terraform apply
terraform output rancher_url                    # https://<dns_label>.<region>.cloudapp.azure.com
```
Installs `cert-manager`, `ingress-nginx` (behind a static public IP in the AKS node RG), and
**Rancher** (`cattle-system`, self-signed TLS). The Rancher hostname is the ingress IP's Azure FQDN
(`<dns_label>.<region>.cloudapp.azure.com`), so no external DNS is required.

## 2. Bootstrap — admin token (run once)
```shell
cd ../rancher-bootstrap
cp terraform.tfvars.example terraform.tfvars   # rancher_url (STACK 1), bootstrap + admin passwords
terraform init && terraform apply
terraform output -raw rancher_api_token         # feed to each fleet cluster stack as rancher_token
```
Optional: set `enable_github_auth=true` + the GitHub OAuth App creds to turn on GitHub login.

## 3. Register a fleet cluster
From the cluster's own stack (e.g. `clusters/azure/sbx/centralus`), set the `rancher` object to
enable registration; the token comes from the environment so it stays out of VCS:
```shell
cd ../../clusters/azure/sbx/centralus
export TF_VAR_rancher_token="<rancher_api_token>"
terraform apply -var 'rancher={url="https://<dns_label>.<region>.cloudapp.azure.com"}'
```
Creates the imported `rancher2_cluster` and applies its registration manifest, installing the
**cattle-cluster-agent** (+ fleet-agent). The module builds a throwaway kubeconfig from the cluster's
own credentials (`module.cluster` outputs), so no local kube-context is needed and it runs the same
from CI; the runner needs `kubectl` + `curl` on PATH. Verify:
```shell
kubectl -n cattle-system get deploy cattle-cluster-agent
# and the cluster shows Active in the Rancher UI
```
Set `tenants` (`{ "<team>" = { group_principal_id = "github_team://<id>" } }`) to also create the 1:1
per-tenant Rancher Projects (empty principal => Project only, no binding).

## Notes
- **TLS:** self-signed (Rancher-generated). Swap to Let's Encrypt / a BYO cert for real use.
- **Version matrix:** `kubernetes_version` and `rancher_version` must be compatible — verify against
  the Rancher release and bump together.
- **Token:** each fleet stack needs the Rancher URL + token. Use `TF_VAR_rancher_token` from a secret
  manager; never commit it.
