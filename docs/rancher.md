# Rancher — why, and how we isolate it

## Why Rancher

Our fleet spans **multiple cloud providers, regions, and environments** (AKS on Azure, EKS on AWS).
Each cloud ships its own identity and cluster-access model — Azure AD / Entra for AKS, IAM Identity
Center for EKS — so without a unifying layer, cluster access is governed by **N different RBAC
systems** that drift apart and are painful to audit.

Rancher is adopted **solely to provide one unified access-management plane** across the whole fleet:

- **One identity model.** Rancher authenticates humans against a single IdP (e.g. GitHub teams) and
  authorizes them with its own global / cluster / **Project** roles, proxying `kubectl` with
  impersonation — the same group drives access on every cluster, regardless of cloud or region.
- **Namespace → Project grouping.** Argo CD creates tenant namespaces; Rancher groups them into a
  per-tenant **Project** (`field.cattle.io/projectId`), so the owning team's access and visibility apply uniformly.
- **Outbound-only agents.** Each cluster registers itself and runs `cattle-cluster-agent`, which dials
  **out** to Rancher. Private API servers need no inbound exposure, and management traffic is control
  plane only — never workload data.

Rancher is **not** used for app delivery (that stays in Argo CD/GitOps) or for quotas/isolation
primitives (those stay Argo-owned). It is an access/RBAC layer, nothing more.

## Failure mode

A Rancher outage does **not** stop deployments or running workloads — Argo CD/GitOps drives delivery
directly against each cluster's API server, independent of Rancher. Only the **Rancher access path**
(the RBAC-proxied `kubectl` / UI) is affected, and **break-glass access via the native cloud IdP —
Entra for AKS, IAM for EKS — covers that** until Rancher is restored. Rancher therefore runs HA with
backup, and availability is never a reason to shard it.

## Rancher isolation / topology

The question: should Rancher be deployed **per environment**, **per region**, or as a **single unified
instance**?

**Shard Rancher by trust boundary, never by geography.**

Region and cloud do not force a split:

- Agents dial outbound and carry only management traffic, so cross-region / cross-cloud latency to a
  single Rancher is irrelevant.
- One Rancher manages AKS **and** EKS together — which is precisely the unified-RBAC value. Splitting
  per region or per cloud fragments the one thing Rancher is there to unify.
- A Rancher outage affects only the access path (see **Failure mode** above), not workloads or
  delivery — so availability is not a reason to shard.

| Option | RBAC model | Blast radius / compliance | Ops overhead | Verdict |
|---|---|---|---|---|
| **Single unified (HA)** | One pane, fully unified | Prod + non-prod share one control plane; one upgrade affects all | Lowest | **Default** |
| **Prod / non-prod split (2 instances)** | Unified within each tier | Prod management isolated; Rancher upgrades tested in non-prod first; tighter prod access governance | Moderate | **Evolution before prod** |
| Per-region | Fragmented | No gain unless data-residency law requires it | High | Avoid |
| Per-environment (sbx/dev/stg/prd) | Heavily fragmented | Overkill | Highest | Avoid |

### Guidance

- **Default:** a **single unified HA Rancher** on a dedicated tools cluster. It matches the unified-RBAC
  intent and spans every cloud, region, and environment.
- **Before onboarding production:** split into **two** HA instances — `rancher-nonprod` and
  `rancher-prod` — to isolate prod's management plane for security, compliance, blast radius, and safe
  Rancher upgrades, while keeping each tier's RBAC unified. Each lives in its **own management
  subscription/account**, separate from workload subscriptions. Structurally this is the `tools/` stack
  parameterized or duplicated per tier.
- **Per-region** only if a data-sovereignty / residency regulation mandates the control plane stay in a
  region.

**Rule of thumb:** one Rancher per trust boundary (prod vs non-prod), HA, in a management account —
not one per region or environment.
