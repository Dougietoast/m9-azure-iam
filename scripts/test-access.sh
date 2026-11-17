#!/usr/bin/env bash
# Runs the M9 access tests AS THE SERVICE PRINCIPAL.
#
#   ./scripts/test-access.sh before   # Part 3: authenticated, but no RBAC yet
#   ./scripts/test-access.sh after    # Part 5: positive + negative tests
#
# The SP signs in to a separate Azure CLI profile (.azure-sp/), so your own
# `az login` session (which Terraform uses) is never replaced.
# No `set -e`: several commands are EXPECTED to fail.

set -uo pipefail

PHASE="${1:-}"
if [[ "$PHASE" != "before" && "$PHASE" != "after" ]]; then
  echo "usage: $0 before|after" >&2
  exit 2
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

# --- Read non-secret values from Terraform outputs (as you) ---------------
TENANT_ID="$(terraform output -raw tenant_id)"
CLIENT_ID="$(terraform output -raw client_id)"
SP_OBJECT_ID="$(terraform output -raw service_principal_object_id)"
ACCOUNT="$(terraform output -raw storage_account_name)"
RG="$(terraform output -raw resource_group_name)"
APP_CONTAINER="$(terraform output -raw app_container_name)"
RESTRICTED_CONTAINER="$(terraform output -raw restricted_container_name)"
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"   # your session, read once
SP_PROFILE="$REPO_DIR/.azure-sp"

STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="evidence/${PHASE}-${STAMP}.log"
mkdir -p evidence

# --- Optional pre-check as YOU: does the SP already hold any role? --------
precheck() {
  echo "### [as deployer] Role assignments held by the SP (incl. inherited)"
  az role assignment list --assignee "$SP_OBJECT_ID" --all --include-inherited \
    --query "[].{role:roleDefinitionName, scope:scope}" -o table 2>&1
  echo "(empty table = no roles at any scope)"
  echo
}

export AZURE_CORE_ONLY_SHOW_ERRORS=true

run() {
  # run "<label>" <command...>  -> prints label, command, output, exit code
  local label="$1"; shift
  echo "### $label"
  echo "\$ $*"
  "$@" 2>&1
  local rc=$?
  echo "exit code: $rc"
  echo
  return 0
}

main() {
  echo "M9 access test - phase: $PHASE - $(date -Is)"
  echo "storage account: $ACCOUNT | app container: $APP_CONTAINER | restricted: $RESTRICTED_CONTAINER"
  echo

  # Pre-check runs with YOUR profile...
  precheck

  # ...everything after this line runs in the SP's own CLI profile.
  export AZURE_CONFIG_DIR="$SP_PROFILE"

  echo "### Authenticate as the service principal"
  # The secret is piped straight from Terraform into az; it is never echoed.
  # --allow-no-subscriptions: the SP has no role on the subscription itself,
  # so without this flag login errors with "No subscriptions found".
  az login --service-principal \
    --username "$CLIENT_ID" \
    --password "$(terraform output -raw client_secret)" \
    --tenant "$TENANT_ID" \
    --allow-no-subscriptions -o none 2>&1
  echo "exit code: $?"
  echo

  run "Confirm the active identity is the service principal" \
    az account show --query "{signedInAs:user.name, identityType:user.type, tenant:tenantId}" -o table

  if [[ "$PHASE" == "before" ]]; then
    run "List blobs in '$APP_CONTAINER' with Entra auth (expect: AuthorizationPermissionMismatch)" \
      az storage blob list --account-name "$ACCOUNT" --container-name "$APP_CONTAINER" \
        --auth-mode login -o table
  else
    local sample="evidence/sample-${STAMP}.txt"
    local downloaded="evidence/downloaded-${STAMP}.txt"
    echo "M9 test report generated ${STAMP} by the reporting service principal" > "$sample"

    run "Upload a blob to '$APP_CONTAINER' (expect: success)" \
      az storage blob upload --account-name "$ACCOUNT" --container-name "$APP_CONTAINER" \
        --name "reports/sample-${STAMP}.txt" --file "$sample" --auth-mode login --overwrite -o table

    run "List blobs in '$APP_CONTAINER' (expect: success)" \
      az storage blob list --account-name "$ACCOUNT" --container-name "$APP_CONTAINER" \
        --auth-mode login --query "[].{name:name, size:properties.contentLength, modified:properties.lastModified}" -o table

    run "Download the blob (expect: success)" \
      az storage blob download --account-name "$ACCOUNT" --container-name "$APP_CONTAINER" \
        --name "reports/sample-${STAMP}.txt" --file "$downloaded" --auth-mode login -o none

    echo "### Verify downloaded content matches the upload"
    if diff -q "$sample" "$downloaded" >/dev/null 2>&1; then
      echo "MATCH: $(cat "$downloaded")"
    else
      echo "MISMATCH or download missing"
    fi
    echo

    run "NEGATIVE (data plane): list blobs in '$RESTRICTED_CONTAINER' (expect: AuthorizationPermissionMismatch)" \
      az storage blob list --account-name "$ACCOUNT" --container-name "$RESTRICTED_CONTAINER" \
        --auth-mode login -o table

    run "NEGATIVE (management plane): read the storage account resource (expect: AuthorizationFailed)" \
      az storage account show --name "$ACCOUNT" --resource-group "$RG" --subscription "$SUBSCRIPTION_ID" \
        --query name -o tsv

    run "NEGATIVE (management plane): list account keys (expect: AuthorizationFailed)" \
      az storage account keys list --account-name "$ACCOUNT" --resource-group "$RG" \
        --subscription "$SUBSCRIPTION_ID" -o table
  fi

  echo "### Sign the service principal out"
  az logout 2>&1
  echo "done."
}

main | tee "$LOG"
echo
echo "Saved log: $LOG"
echo "Note: role assignments can take a few minutes to take effect. If 'after' shows"
echo "denied right after an apply, wait ~5 minutes and run it again before changing anything."
