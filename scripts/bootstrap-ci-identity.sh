#!/usr/bin/env bash
# bootstrap-ci-identity.sh — create the CI/CD image push + promotion identities for a tenant.
#
# Creates passwordless User-Assigned Managed Identities (UAMIs) with GitHub OIDC federated
# credentials and least-privilege ACR role assignments, in a dedicated PER-TENANT identity RG that is
# decoupled from any cluster (so recreating a cluster never deletes the identities and the GitHub
# client-ID secrets stay stable). Two identities per tenant:
#
#   ci-publisher-<tenant>   ONE identity shared by all the tenant's service repos (one federated
#                           credential per repo in SERVICE_REPOS). AcrPush on the SBX azure ACR.
#                           This is what each service's CI (<repo>/cd.yml) uses to push the sbx image.
#
#   promote-<tenant>        AcrPull on the SBX ACR (source) + AcrPush on the DEV ACR (target).
#                           Federated to the tenant's gitops repo (promote.yml, workflow_dispatch).
#                           Used by the promotion flow to `cosign copy` the digest sbx ACR -> dev ACR.
#
# Identities live in rg-platform-identity-<tenant>-<region>; only the ACR role assignments are
# cluster-coupled and are re-applied idempotently after a cluster rebuild.
#
# Idempotent: safe to re-run. Prints the GitHub repo secret values at the end.
#
# NOTE (paved road): this script is the fast path. The durable form is a reusable Terraform module
# (modules/ci-identity) instantiated in the cluster stacks.
#
# Prereqs: az CLI logged in (PIM activated) with Contributor + User Access Administrator on the
# subscription. Requires jq and gh.
set -euo pipefail

# ----------------------------------------------------------------------------- config
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-00000000-0000-0000-0000-000000000000}"
GITHUB_ORG="${GITHUB_ORG:-imkrupakar}"

# Region: LOCATION is the Azure region; REGION_SHORT is the name suffix used in RG names.
LOCATION="${LOCATION:-centralus}"
REGION_SHORT="${REGION_SHORT:-cus}"

# Tenant (team) that owns the identities + services.
TENANT="${TENANT:-team-alpha}"

# SBX azure cluster (CI pushes here; promotion reads from here).
SBX_RG="${SBX_RG:-rg-platform-sbx-${REGION_SHORT}}"
# DEV azure cluster (promotion target). Skipped automatically if it doesn't exist yet.
DEV_RG="${DEV_RG:-rg-platform-dev-${REGION_SHORT}}"

# Per-tenant, long-lived identity RG (NOT a cluster RG) — survives cluster rebuilds.
IDENTITY_RG="${IDENTITY_RG:-rg-platform-identity-${TENANT}-${REGION_SHORT}}"

# One CI-publisher identity for ALL the tenant's services; one promote identity for its gitops repo.
CI_UAMI="${CI_UAMI:-ci-publisher-${TENANT}}"
PROMOTE_UAMI="${PROMOTE_UAMI:-promote-${TENANT}}"

# Space/comma-separated list of the tenant's service repos the CI-publisher federates to.
SERVICE_REPOS="${SERVICE_REPOS:-orders-api}"
GITOPS_REPO="${GITOPS_REPO:-${TENANT}-gitops}"        # repo promote.yml runs in
# Optional stable release branch to also federate for CI (e.g. releases/M1). Empty = skip.
CI_RELEASE_BRANCH="${CI_RELEASE_BRANCH:-}"

# ACR overrides (otherwise discovered from the cluster RG at runtime).
SBX_ACR="${SBX_ACR:-}"
DEV_ACR="${DEV_ACR:-}"

ISSUER="https://token.actions.githubusercontent.com"
AUDIENCE="api://AzureADTokenExchange"

az account set --subscription "$SUBSCRIPTION_ID"
TENANT_ID="$(az account show --query tenantId -o tsv)"

# ----------------------------------------------------------------------------- helpers
log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }

# Discover an ACR id from a cluster RG (or an explicit ACR name). Echoes the id, or empty if none.
acr_id() {         # <rg> <acr-name-or-empty>
  local rg="$1" name="$2"
  if [ -n "$name" ]; then
    az acr show -n "$name" -g "$rg" --query id -o tsv 2>/dev/null || true
  else
    az acr list -g "$rg" --query '[0].id' -o tsv 2>/dev/null || true
  fi
}

ensure_rg() {      # <rg>
  local rg="$1"
  az group show -n "$rg" >/dev/null 2>&1 || { log "creating RG $rg"; az group create -n "$rg" -l "$LOCATION" -o none; }
}

ensure_uami() {    # <rg> <name>  -> sets globals UAMI_CLIENT_ID / UAMI_PRINCIPAL_ID
  local rg="$1" name="$2"
  az identity show -g "$rg" -n "$name" >/dev/null 2>&1 || \
    az identity create -g "$rg" -n "$name" -l "$LOCATION" -o none
  # Newly created identities can take a moment to be queryable.
  for _ in 1 2 3 4 5; do
    UAMI_CLIENT_ID="$(az identity show -g "$rg" -n "$name" --query clientId -o tsv 2>/dev/null || true)"
    UAMI_PRINCIPAL_ID="$(az identity show -g "$rg" -n "$name" --query principalId -o tsv 2>/dev/null || true)"
    [ -n "$UAMI_CLIENT_ID" ] && [ -n "$UAMI_PRINCIPAL_ID" ] && return 0
    sleep 3
  done
  echo "::error:: could not read identity $name" >&2; return 1
}

ensure_fic() {     # <rg> <uami> <fic-name> <subject>
  local rg="$1" uami="$2" fic="$3" subject="$4" existing
  if existing="$(az identity federated-credential show -g "$rg" --identity-name "$uami" --name "$fic" --query subject -o tsv 2>/dev/null)"; then
    if [ "$existing" = "$subject" ]; then
      log "federated credential '$fic' already matches ($subject)"
    else
      log "updating federated credential '$fic' subject -> $subject"
      az identity federated-credential update -g "$rg" --identity-name "$uami" --name "$fic" \
        --issuer "$ISSUER" --subject "$subject" --audiences "$AUDIENCE" -o none
    fi
  else
    log "creating federated credential '$fic' ($subject)"
    az identity federated-credential create -g "$rg" --identity-name "$uami" --name "$fic" \
      --issuer "$ISSUER" --subject "$subject" --audiences "$AUDIENCE" -o none
  fi
}

# GitHub's OIDC subject prefix for a repo. With immutable subjects enabled it is
# "repo:<org>@<orgid>/<repo>@<repoid>"; otherwise "repo:<org>/<repo>". Auto-detected via the API so
# the federated credential always matches the token GitHub actually presents.
gh_sub_prefix() {  # <owner/repo> -> echoes subject prefix
  local repo="$1" prefix
  prefix="$(gh api "/repos/${repo}/actions/oidc/customization/sub" --jq '.sub_claim_prefix // ""' 2>/dev/null || true)"
  [ -n "$prefix" ] && { echo "$prefix"; return 0; }
  echo "repo:${repo}"
}

ensure_role() {    # <principalId> <role> <scope>
  local principal="$1" role="$2" scope="$3"
  if az role assignment list --assignee "$principal" --scope "$scope" \
       --query "[?roleDefinitionName=='$role']" -o tsv 2>/dev/null | grep -q .; then
    log "role '$role' already assigned on $(basename "$scope")"
  else
    log "assigning '$role' on $(basename "$scope")"
    az role assignment create --assignee-object-id "$principal" \
      --assignee-principal-type ServicePrincipal --role "$role" --scope "$scope" -o none
  fi
}

# ----------------------------------------------------------------------------- resolve scopes
ensure_rg "$IDENTITY_RG"

SBX_ACR_ID="$(acr_id "$SBX_RG" "$SBX_ACR")"
[ -n "$SBX_ACR_ID" ] || { echo "::error:: no ACR found in $SBX_RG (set SBX_ACR or create the sbx cluster)"; exit 1; }
DEV_ACR_ID="$(acr_id "$DEV_RG" "$DEV_ACR")"

# ----------------------------------------------------------------------------- CI publisher (one per tenant)
log "CI publisher identity: $CI_UAMI (AcrPush on $(basename "$SBX_ACR_ID"); repos: $SERVICE_REPOS)"
ensure_uami "$IDENTITY_RG" "$CI_UAMI"
CI_CLIENT_ID="$UAMI_CLIENT_ID"; CI_PRINCIPAL_ID="$UAMI_PRINCIPAL_ID"
for repo in ${SERVICE_REPOS//,/ }; do
  prefix="$(gh_sub_prefix "${GITHUB_ORG}/${repo}")"
  ensure_fic "$IDENTITY_RG" "$CI_UAMI" "${repo}-main" "${prefix}:ref:refs/heads/main"
  if [ -n "$CI_RELEASE_BRANCH" ]; then
    ensure_fic "$IDENTITY_RG" "$CI_UAMI" "${repo}-$(echo "$CI_RELEASE_BRANCH" | tr '/' '-')" \
      "${prefix}:ref:refs/heads/${CI_RELEASE_BRANCH}"
  fi
done
ensure_role "$CI_PRINCIPAL_ID" "AcrPush" "$SBX_ACR_ID"

# ----------------------------------------------------------------------------- Promotion
log "Promotion identity: $PROMOTE_UAMI (AcrPull on sbx + AcrPush on dev)"
ensure_uami "$IDENTITY_RG" "$PROMOTE_UAMI"
PROMOTE_CLIENT_ID="$UAMI_CLIENT_ID"; PROMOTE_PRINCIPAL_ID="$UAMI_PRINCIPAL_ID"
PROMOTE_PREFIX="$(gh_sub_prefix "${GITHUB_ORG}/${GITOPS_REPO}")"
ensure_fic "$IDENTITY_RG" "$PROMOTE_UAMI" "${GITOPS_REPO}-main" \
  "${PROMOTE_PREFIX}:ref:refs/heads/main"
ensure_role "$PROMOTE_PRINCIPAL_ID" "AcrPull" "$SBX_ACR_ID"
if [ -n "$DEV_ACR_ID" ]; then
  ensure_role "$PROMOTE_PRINCIPAL_ID" "AcrPush" "$DEV_ACR_ID"
else
  warn "no ACR found in $DEV_RG — skipping the promotion AcrPush (dev cluster not provisioned yet). Re-run once dev exists."
fi

# ----------------------------------------------------------------------------- summary
cat <<EOF

============================================================================
 Bootstrap complete for tenant '${TENANT}'. Identities live in: ${IDENTITY_RG}
 Set these GitHub repo secrets (role propagation ~1-2 min):

 On EACH service repo (${SERVICE_REPOS}):
   AZURE_CLIENT_ID        = ${CI_CLIENT_ID}
   AZURE_TENANT_ID        = ${TENANT_ID}
   AZURE_SUBSCRIPTION_ID  = ${SUBSCRIPTION_ID}

 Repo: ${GITHUB_ORG}/${GITOPS_REPO}
   AZURE_PROMOTE_CLIENT_ID = ${PROMOTE_CLIENT_ID}
   AZURE_TENANT_ID         = ${TENANT_ID}
   AZURE_SUBSCRIPTION_ID   = ${SUBSCRIPTION_ID}

 Convenience:
   CI_CLIENT_ID=${CI_CLIENT_ID}
   PROMOTE_CLIENT_ID=${PROMOTE_CLIENT_ID}
   TENANT_ID=${TENANT_ID}
   SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
============================================================================
EOF
