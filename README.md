# platform-terraform

**Separate repository.** Provisions each Kubernetes cluster and bootstraps a **standalone Argo CD
per cluster**. There is no hub — every cluster manages only itself from Git. Once Argo CD is running,
everything else (add-ons, tenants, workloads) is reconciled from `platform-gitops`; this repo is the
imperative, run-once part.

## What Terraform does (per cluster)

The cluster stack (`clusters/<cloud>/<env>/<region>/`) provisions everything in a **single
`terraform apply`** — no `-target` passes. It groups into two logical stages:

**Infrastructure**
1. Create the cluster + its network + registry:
   - Azure: `modules/aks-cluster` (AKS + VNet) and an `azurerm_container_registry` (ACR) in the stack.
   - AWS: `modules/eks-cluster` (EKS + VPC, a thin wrapper over the standard `terraform-aws-modules`)
     and `aws_ecr_repository` resources in the stack.

**Hand control to GitOps**
2. Install the **foundational Gateway API CRDs** (`modules/gateway-api-crds`, pinned by
   `gateway_api_version`) — a cluster capability, like Argo CD itself, so it is owned by Terraform
   rather than GitOps.
3. Install Argo CD (`modules/argocd-bootstrap` → Helm, pinned by `argocd_chart_version`).
4. Create the **labeled in-cluster secret** (`environment`, `region`, `cloud`, `workloads`) — this is
   how the platform ApplicationSets discover the cluster's identity and render the right config.
5. Seed the GitHub App `repo-creds` secret (so Argo CD can read private Git).
6. Apply the **one** root Application (app-of-apps) pointing at `platform-gitops`.

After that, Argo CD self-manages with **zero kubectl**.

## Layout

```
platform-terraform/
├── fleet.yaml               # registry of every cluster + its pinned versions (promotion ledger)
├── modules/
│   ├── aks-cluster/         # AKS + VNet (raw azurerm)
│   ├── eks-cluster/         # EKS + VPC (wraps terraform-aws-modules/{vpc,eks})
│   ├── gateway-api-crds/    # foundational Gateway API CRDs (http + kubectl, server-side apply)
│   └── argocd-bootstrap/    # install Argo CD + in-cluster label + repo-creds + root app
└── clusters/                # one stack per CLUSTER, keyed <cloud>/<env>/<region>, local state
    ├── azure/sbx/centralus/ # AKS + ACR + Argo CD
    └── aws/sbx/us-east-2/    # EKS + ECR + Argo CD
```

Each cluster stack is thin: `terraform.tfvars` carries identity + pins, `main.tf` wires the providers
and calls the modules. The ACR/ECR registries are created in the stack itself (ECR has no registry
resource — each repository is its own `aws_ecr_repository`). The provider set includes **kubectl**
(`gavinbunney/kubectl`): the root Application is applied with `kubectl_manifest`, not
`kubernetes_manifest`, because the latter needs the Argo CD `Application` CRD to exist at plan time
(it is installed by the Helm release in the same apply).

## Version pinning & promotion

Each cluster pins its own versions **explicitly** in `terraform.tfvars` and promotes them one cluster
at a time (sbx → dev → stg → prd):

- `argocd_chart_version` — the `argo-cd` Helm chart.
- `gateway_api_version` — the Gateway API CRD bundle.

(The GitOps side has its own per-cluster ledger in `platform-gitops/envs/<env>/<cloud>/<region>/versions.yaml`
for add-ons + the platform-config chart.) `fleet.yaml` is the human-readable index of the whole fleet
and the intended version matrix.

> **CI check (monotonic promotion).** Every pull request that touches the stacks, modules, or
> `fleet.yaml` runs `scripts/validate_fleet.py` (in `terraform-ci.yml`), which enforces that a
> module/chart version never lands in a higher environment before the next-lower one already runs it
> (`sbx → dev → stg → prd`), that every `fleet.yaml` entry has a live stack, and that any git-pinned
> module `?ref` matches its `fleet.yaml` entry (drift guard). So promotion is always a reviewable,
> ordered diff — you can't accidentally pin prd ahead of stg.

## Adding a cluster (new env / region / cloud)

1. Copy the nearest same-cloud stack to `clusters/<cloud>/<env>/<region>/` and set its `terraform.tfvars`
   (identity + pins). A brand-new cloud also needs a `modules/<cloud>-cluster` module.
2. Add a `platform-gitops/envs/<env>/<cloud>/<region>/versions.yaml` (add-on + platformConfig pins) so
   the new cluster renders the platform stack.
3. Add the cluster to `fleet.yaml`.
4. Apply:
   ```
   terraform init
   export TF_VAR_github_app_private_key="$(cat argocd-app.pem)"
   terraform apply                                                # cluster + CRDs + Argo CD, one pass
   ```
   For a brand-new cluster whose GitHub App doesn't exist yet, apply once with `enable_argocd=false`
   to stand up infra, create the App, then re-apply with `enable_argocd=true` and the creds set.

The cluster self-labels and its Argo CD pulls the entire platform + tenant workloads from Git — **no
change to `platform-gitops` beyond the seeded `versions.yaml`**.

## Boundary with platform-gitops

- **This repo** owns cluster creation, foundational CRDs, and the Argo CD entry point (imperative, run-once).
- **`platform-gitops`** owns everything Argo CD reconciles afterward (declarative, forever).
- The root Application is applied here but points at `platform-gitops/bootstrap/app-of-apps`.
