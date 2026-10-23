# CI/CD image delivery & promotion (per-cluster registry)

How a team service (e.g. `orders-api`) gets built once and delivered to every cluster in this
platform, and the identities/permissions that make it work. This is the paved road Platform
Engineering owns; a team only edits its own leaf + source repo.

## Registry topology: one registry per cluster

Each cluster has its **own** container registry (one ACR per Azure cluster, one ECR per AWS
cluster). The image is **built once** (immutable digest) and **copied by digest** into each
cluster's registry as it is promoted — never rebuilt.

**Where the topology lives (single source of truth):** the PE-owned repo **`platform-actions`**
holds `catalog.yaml` — a hierarchy of shareable platform facts (`defaults → environments.<env> →
clouds.<cloud> → regions.<region>`). A fact is set at the level it applies to and inherited
downward; a cluster's `registry` is read at the deepest level that defines it. Onboarding a new
cluster's registry = set its `regions.<region>.registry` (facts shared by a whole env/cloud — a
subscription, an AWS account — are set once at that level).

Team GitOps repos do **not** keep their own copy; their `promote.yml` and `validate.yml` are
**thin callers** of the reusable workflows in `platform-actions` (the same pattern as the
`validate-team-repo.yml` that already lived in the platform). See `platform-actions/README.md`.

Each cluster leaf (`apps/<svc>/envs/<env>/<cloud>/<region>/values.yaml`) still carries its own
`image.repository` (that cluster's registry), `tag`, and `digest` — written by the promotion
workflow from `catalog.yaml`. CI writes only the sbx leaf; every higher ring is a gated promotion.

## Identities & permissions (passwordless, least privilege)

Provisioned by `platform-terraform/scripts/bootstrap-ci-identity.sh` (POC bootstrap; the durable
form is a reusable Terraform module — see "Follow-ups"). Two User-Assigned Managed Identities,
each with a **GitHub OIDC federated credential** (no secrets, no PATs):

| Identity | Federated to (OIDC subject) | ACR rights | Used by |
|---|---|---|---|
| `ci-publisher-orders-api` | `orders-api` `:ref:refs/heads/main` (+ `releases/M*`) | **AcrPush on the sbx ACR only** | `orders-api/cd.yml` |
| `promote-team-alpha` | `team-alpha-gitops` `:ref:refs/heads/main` | **AcrPull on source ACR + AcrPush on next-ring ACR** | `team-alpha-gitops/promote.yml` |

Cluster kubelets already get **AcrPull on their own ACR** (provisioned in each cluster's Terraform
stack). CI can push sbx and nothing else; promotion can copy into the next ring and nothing else —
least privilege is enforced at the role layer, not just by convention.

> **Immutable OIDC subjects.** These repos have `use_immutable_subject: true`, so GitHub presents
> `repo:<org>@<orgid>/<repo>@<repoid>:ref:...`. The bootstrap script auto-detects the subject
> prefix from the GitHub API, so the federated credential always matches the presented token.

### GitHub repo secrets (set from the script output)

- `orders-api`: `AZURE_CLIENT_ID` (ci-publisher), `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`,
  `GITOPS_PAT` (write token to the team GitOps repo; a GitHub App is the target — see Follow-ups).
- `team-alpha-gitops`: `AZURE_PROMOTE_CLIENT_ID` (promotion), `AZURE_TENANT_ID`,
  `AZURE_SUBSCRIPTION_ID`.
- Repo setting: *Allow GitHub Actions to create and approve pull requests* must be ON (the promote
  workflow opens the promotion PR).

## The flow

1. **CI (`orders-api/cd.yml`)** on push to `main`/`releases/M*`: GitVersion → build once (SBOM +
   provenance) → discover the sbx registry from the sbx leaf → push + **cosign keyless sign** →
   pin the sbx leaf (`tag` + `digest`). Argo CD on sbx reconciles.
2. **Promotion (`team-alpha-gitops/promote.yml` → reusable `platform-actions/.github/workflows/promote.yml`,
   `workflow_dispatch`)**: the thin caller forwards inputs + `secrets: inherit`; the reusable
   workflow resolves the source/target registries from `platform-actions/catalog.yaml` (via the
   `resolve-registry` composite action), validates the ring (sbx→dev→stg→prd, canary-first,
   stable-only into stg/prd, provenance) → **`cosign copy`s the exact digest (with its signature)
   into the target cluster's ACR** → pins the target leaf (`repository` + `tag` + `digest`) →
   opens a CODEOWNERS-gated PR. Merge = deploy; revert = rollback.
3. **PR validation (`team-alpha-gitops/validate.yml` → reusable
   `platform-actions/.github/workflows/validate-team-repo.yml`)**: runs the platform policy tool
   (`check_team_layout.py`, checked out from `platform-gitops`) on every PR.

## Verified (POC, 2026-10)

- **Image push** end-to-end on the live **sbx/azure** cluster: CI built `0.1.0`, pushed to
  `acrplatsbxcus14462b`, signed, pinned the sbx leaf; Argo CD rolled new pods on the CI-built
  digests (`d3c785…`, then `cb939e73…`).
- **Promotion** sbx/azure → dev/azure through the **reusable `platform-actions` workflow**: resolved
  the registries from `catalog.yaml`, copied the exact digest (+ signature) into the dev cluster's
  own ACR `acrplatdevcus5826df`, created/pinned the `dev/azure/centralus` leaf (dev-ACR repository,
  same digest), opened the PR, merged.
- **Validate** runs from `platform-actions` on a PR and is **green** (`PLATFORM_READ_TOKEN` set on
  the team repo so the policy tool + fleet can be checked out).
  (The dev-cluster pod roll-out was not observed from the POC workstation because the dev API
  server is private and the operator's PIM was scoped to the sbx resource group; the registry +
  GitOps mechanics are proven and Argo CD reconciles the leaf once the cluster is reachable.)

## Follow-ups

- **Codify identities into Terraform** (`modules/ci-identity`): a reusable module that takes a
  cluster ACR + a list of `{repo, branch, role}` and emits the UAMI, OIDC federated credentials,
  and role assignments. Replaces the bootstrap script so new repos/clusters come from
  `terraform apply`. The script remains the fast path and documents the exact resources to encode.
- **AWS onboarding** (per-cluster ECR): mirror the Azure model for the AWS clusters —
  - a **GitHub OIDC IAM role** (CI publisher) with `ecr:*Push*` on the sbx **ECR only**, and a
    promotion IAM role with pull on source + push on the next-ring ECR;
  - create the per-cluster ECR repos; set their hosts under the clusters in
    `platform-actions/catalog.yaml`;
  - CI/promotion already `cosign copy` by digest into ECR (carries signatures); re-enable the
    AWS copy block in `cd.yml` (currently gated off for the Azure-first iteration).
- **Generate `platform-actions/catalog.yaml` from Terraform** (`fleet.yaml` + each stack's
  `acr_login_server`/RG/vault outputs) so the central catalog can't drift from what TF creates.
- **GitOps write via a GitHub App** instead of `GITOPS_PAT` (fine-grained, PE-owned, no personal
  token).
- **prd gating**: put the promotion identity's prd ACR push behind a GitHub **Environment** with
  required reviewers.
- **Optional:** have `orders-api/cd.yml` resolve the sbx registry via the same `resolve-registry`
  action (instead of reading the leaf) for full single-source-of-truth consistency.
