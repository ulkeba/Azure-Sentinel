#!/usr/bin/env bash
set -euo pipefail

######## ADD YOUR RESOURCE IDS HERE
WORKSPACE_ID="/subscriptions/.../resourceGroups/.../providers/Microsoft.OperationalInsights/workspaces/...    <--- The full resource ID of the target Log Analytics Workspace"
########

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TABLE_DEFINITION="$SCRIPT_DIR/table-orca.json"
TABLE_NAME="SAPOrca_CL"
TABLE_API_VERSION="2025-02-01"
TABLE_ID="$WORKSPACE_ID/tables/$TABLE_NAME"

for command_name in az jq; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Required command not found: $command_name" >&2
        exit 1
    fi
done

if [[ ! -f "$TABLE_DEFINITION" ]]; then
    echo "Table definition not found: $TABLE_DEFINITION" >&2
    exit 1
fi

az account show --output none

payload_file="$(mktemp)"
trap 'rm -f "$payload_file"' EXIT

jq '{properties: .properties}' "$TABLE_DEFINITION" >"$payload_file"

echo "Creating or updating $TABLE_NAME in c2s-sentinel-d03-law..."
az rest \
    --method put \
    --url "https://management.azure.com${TABLE_ID}?api-version=${TABLE_API_VERSION}" \
    --headers "Content-Type=application/json" \
    --body "@$payload_file" \
    --output none

provisioning_state="$(az rest \
    --method get \
    --url "https://management.azure.com${TABLE_ID}?api-version=${TABLE_API_VERSION}" \
    --query properties.provisioningState \
    --output tsv)"

echo "$TABLE_NAME provisioning state: ${provisioning_state:-unknown}"