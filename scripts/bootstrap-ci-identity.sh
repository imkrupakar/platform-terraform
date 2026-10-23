#!/usr/bin/env bash
# bootstrap-ci-identity.sh — POC bootstrap for the CI/CD image push + promotion identities.
#
# Creates two passwordless User-Assigned Managed Identities (UAMIs) with GitHub OIDC federated
# credentials and least-privilege ACR role assignments, for the per-cluster ACR topology:
#
#   ci-publisher-orders-api   AcrPush on the SBX azure ACR only.
#                             Federated to orders-api  main  (+ a release branch, optional).
#                             This is what CI (orders-api/cd.yml) uses to push the sbx image.
#
#   promote-team-alpha        AcrPull on the SBX ACR (source) + AcrPush on the DEV ACR (target).
#                             Federated to team-alpha-gitops main (promote.yml, workflow_dispatch).
#                             This is what the promotion flow uses to `cosign copy` the digest
#                             from the sbx ACR into the dev cluster's ACR.
#
# Idempotent: safe to re-run. Prints the GitHub repo secret values at the end.
#
# NOTE (paved road): this script is the fast POC path. The durable form is a reusable Terraform
# module (modules/ci-identity) instantiated in the cluster stacks — see plan todo `codify-tf-followup`.
#
# Prereqs: az CLI logged in (PIM activated) with Contributor + User Access Administrator on the
# subscription. Requires jq.
set -euo pipefail

# ----------------------------------------------------------------------------- config
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-c556d760-610e-4ac0-a522-dc67de95d763}"
LOCATION="${LOCATION:-centralus}"
GITHUB_ORG="${GITHUB_ORG:-krupakar-hyland}"

# SBX azure cluster (CI pushes here; promotion reads from here)
SBX_RG="${SBX_RG:-rg-platform-sbx-cus}"
SBX_ACR="${SBX_ACR:-acrplatsbxcus14462b}"

# DEV azure cluster (promotion target)
DEV_RG="${DEV_RG:-rg-platform-dev-cus}"
DEV_ACR="${DEV_ACR:-acrplatdevcus5826df}"

# Identities live in the sbx platform RG for the POC.
IDENTITY_RG="${IDENTITY_RG:-$SBX_RG}"

CI_UAMI="${CI_UAMI:-ci-publisher-orders-api}"
PROMOTE_UAMI="${PROMOTE_UAMI:-promote-team-alpha}"

CI_REPO="${CI_REPO:-orders-api}"                       # source repo CI runs in
GITOPS_REPO="${GITOPS_REPO:-team-alpha-gitops}"        # repo promote.yml runs in
# Optional stable release branch to also federate for CI (e.g. releases/M1). Empty = skip.
CI_RELEASE_BRANCH="${CI_RELEASE_BRANCH:-}"

ISSUER="https://token.actions.githubusercontent.com"
AUDIENCE="api://AzureADTokenExchange"

az account set --subscription "$SUBSCRIPTION_ID"
TENANT_ID="$(az account show --query tenantId -o tsv)"
SBX_ACR_ID="$(az acr show -n "$SBX_ACR" -g "$SBX_RG" --query id -o tsv)"
DEV_ACR_ID="$(az acr show -n "$DEV_ACR" -g "$DEV_RG" --query id -o tsv)"

# ----------------------------------------------------------------------------- helpers
log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

ensure_uami() {    # <rg> <name>  -> echoes "<clientId>\n<principalId>"; sets globals UAMI_CLIENT_ID/UAMI_PRINCIPAL_ID
  local rg="$1" name="$2" i
  az identity show -g "$rg" -n "$name" >/dev/null 2>&1 || \
    az identity create -g "$rg" -n "$name" -l "$LOCATION" -o none
  # Newly created identities can take a moment to be queryable.
  for i in 1 2 3 4 5; do
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

# ----------------------------------------------------------------------------- CI publisher
log "CI publisher identity: $CI_UAMI (AcrPush on $SBX_ACR)"
ensure_uami "$IDENTITY_RG" "$CI_UAMI"
CI_CLIENT_ID="$UAMI_CLIENT_ID"; CI_PRINCIPAL_ID="$UAMI_PRINCIPAL_ID"
CI_PREFIX="$(gh_sub_prefix "${GITHUB_ORG}/${CI_REPO}")"
ensure_fic "$IDENTITY_RG" "$CI_UAMI" "${CI_REPO}-main" \
  "${CI_PREFIX}:ref:refs/heads/main"
if [ -n "$CI_RELEASE_BRANCH" ]; then
  ensure_fic "$IDENTITY_RG" "$CI_UAMI" "${CI_REPO}-$(echo "$CI_RELEASE_BRANCH" | tr '/' '-')" \
    "${CI_PREFIX}:ref:refs/heads/${CI_RELEASE_BRANCH}"
fi
ensure_role "$CI_PRINCIPAL_ID" "AcrPush" "$SBX_ACR_ID"

# ----------------------------------------------------------------------------- Promotion
log "Promotion identity: $PROMOTE_UAMI (AcrPull on $SBX_ACR + AcrPush on $DEV_ACR)"
ensure_uami "$IDENTITY_RG" "$PROMOTE_UAMI"
PROMOTE_CLIENT_ID="$UAMI_CLIENT_ID"; PROMOTE_PRINCIPAL_ID="$UAMI_PRINCIPAL_ID"
PROMOTE_PREFIX="$(gh_sub_prefix "${GITHUB_ORG}/${GITOPS_REPO}")"
ensure_fic "$IDENTITY_RG" "$PROMOTE_UAMI" "${GITOPS_REPO}-main" \
  "${PROMOTE_PREFIX}:ref:refs/heads/main"
ensure_role "$PROMOTE_PRINCIPAL_ID" "AcrPull" "$SBX_ACR_ID"
ensure_role "$PROMOTE_PRINCIPAL_ID" "AcrPush" "$DEV_ACR_ID"

# ----------------------------------------------------------------------------- summary
cat <<EOF

============================================================================
 Bootstrap complete. Set these GitHub repo secrets (role propagation ~1-2 min):

 Repo: ${GITHUB_ORG}/${CI_REPO}
   AZURE_CLIENT_ID        = ${CI_CLIENT_ID}
   AZURE_TENANT_ID        = ${TENANT_ID}
   AZURE_SUBSCRIPTION_ID  = ${SUBSCRIPTION_ID}

 Repo: ${GITHUB_ORG}/${GITOPS_REPO}
   AZURE_PROMOTE_CLIENT_ID = ${PROMOTE_CLIENT_ID}
   AZURE_TENANT_ID         = ${TENANT_ID}
   AZURE_SUBSCRIPTION_ID   = ${SUBSCRIPTION_ID}

 Convenience (pipe to the gh calls in repo-secrets step):
   CI_CLIENT_ID=${CI_CLIENT_ID}
   PROMOTE_CLIENT_ID=${PROMOTE_CLIENT_ID}
   TENANT_ID=${TENANT_ID}
   SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
============================================================================
EOF
