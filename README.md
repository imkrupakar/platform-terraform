# cluster-platform-terraform

**Separate repository.** Provisions each Kubernetes cluster and bootstraps a **standalone
Argo CD per cluster**. There is no hub — every cluster manages only itself from Git.

## What Terraform does (Phase 1, once per cluster)

1. Create the cluster (AKS or EKS) — `modules/aks-cluster` / `modules/eks-cluster`.
2. Install Argo CD on that cluster (`modules/argocd-bootstrap` → Helm).
3. Create the **labeled in-cluster secret** so Argo CD knows its own identity
   (`environment`, `region`, `cloud`, `workloads`). The platform ApplicationSets read
   these labels via the cluster generator.
4. Seed the single GitHub App `repo-creds` secret (so Argo CD can read private Git).
5. Apply the **one** root Application (app-of-apps) pointing at `platform-gitops`.

After that, Argo CD self-manages: add-ons (incl. ESO), AppProjects, tenant namespaces,
and workloads all reconcile from Git with **zero kubectl**.

## Layout

```
cluster-platform-terraform/
├── fleet.yaml               # SOURCE OF TRUTH: every cluster + its pinned module/chart versions
├── modules/                 # consumed via a PINNED git ?ref (promotable)
│   ├── aks-cluster/         # provision AKS (placeholder for your real module)
│   ├── eks-cluster/         # provision EKS (placeholder)
│   ├── gke-cluster/         # provision GKE (placeholder — new-cloud readiness)
│   ├── argocd-bootstrap/    # install Argo CD + in-cluster label + repo-creds + root app
│   ├── acr/                 # one Azure Container Registry (reused for nonprod + prod)
│   └── ecr/                 # one regional AWS ECR registry (prod)
├── clusters/                # one stack per CLUSTER (own state): <cloud>/<env>/<region>
│   ├── azure/
│   │   ├── sbx/eastus/
│   │   ├── dev/eastus/
│   │   ├── stg/eastus/
│   │   └── prd/{eastus,westus}/
│   └── aws/
│       └── prd/us-east-1/
└── platform/                # FLEET-WIDE infra (not per-cluster): own state per stack
    └── registry/            # layout: <cloud>/<tier>[/<region>]
        ├── azure/
        │   ├── nonprod/     # nonprod ACR (one registry; no <region> — see below)
        │   └── prod/        # prod ACR, geo-replicated to all Azure prod regions
        └── aws/
            ├── nonprod/<region>/  # nonprod ECR (ECR is regional -> one stack per region)
            └── prod/<region>/     # prod ECR     (and per AWS account per tier)
```

`clusters/` holds per-cluster stacks; `platform/` holds shared singletons (the registries,
and later DNS/global LB, shared identity). Keeping them apart means a registry change never
re-plans a cluster and vice versa. Each cluster stack is thin: `terraform.tfvars` +
`backend.tf` carry identity, `main.tf` wires providers and calls the pinned modules. The
provider set includes **kubectl** (`gavinbunney/kubectl`) — the root Application is applied
with `kubectl_manifest`, not `kubernetes_manifest`, because the latter needs the Argo CD
`Application` CRD to exist at plan time (it is installed by the Helm release in the same apply).

## Versioned modules & promotion

Module sources are pinned to a release tag and promoted lower→higher env:

```hcl
module "cluster" {
  source = "git::https://github.com/krupakar-hyland/cluster-platform-terraform.git//modules/aks-cluster?ref=v1.0.0"
}
module "argocd" {
  source = "git::.../modules/argocd-bootstrap?ref=v1.0.0"
}
```

Ladder: bump the `?ref` (and `argocd_chart_version`) in the **sbx** stack → `apply` → soak →
advance **dev** → **stg** → **prd**. `fleet.yaml` records the version matrix per cluster and
is the drift guard (CI checks each stack's `?ref` equals its fleet entry, and that a version
never lands in a higher env before the next-lower env runs it).

## Adding a cluster (new env / region / cloud)

Run `scripts/onboard-cluster.sh <cloud> <env> <region>` (clones the nearest same-cloud stack,
rewrites identity + backend key, prints the `fleet.yaml` entry), add the fleet entry, then
`terraform apply`. The new cluster provisions, installs its own Argo CD, self-labels
(environment/region/cloud), and pulls the entire platform + tenant workloads from Git.
**No change to `platform-gitops`.** A new cloud additionally needs a `modules/<cloud>-cluster`
module (a `gke-cluster` stub is included).

## Boundary with platform-gitops

- This repo owns **cluster creation + the Argo CD entry point** (imperative, once).
- `platform-gitops` owns **everything Argo CD reconciles afterward** (declarative, forever).
- The root Application manifest is applied here but points at
  `platform-gitops/bootstrap/app-of-apps`.
