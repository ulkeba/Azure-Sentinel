#!/usr/bin/env bash
set -euo pipefail

######## ADD YOUR RESOURCE IDS HERE
WORKSPACE_ID="/subscriptions/.../resourceGroups/.../providers/Microsoft.OperationalInsights/workspaces/...    <--- The full resource ID of the target Log Analytics Workspace"
DCR_ID="/subscriptions/.../resourceGroups/.../providers/Microsoft.Insights/dataCollectionRules/...    <--- The full resource ID of the Data Collection Rule"
########

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DCR_DEFINITION="$SCRIPT_DIR/SAPLogServ_DCR.json"
DCR_API_VERSION="2023-03-11"
TABLE_ID="$WORKSPACE_ID/tables/SAPOrca_CL"
TABLE_API_VERSION="2025-02-01"

for command_name in az jq; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Required command not found: $command_name" >&2
        exit 1
    fi
done

if [[ ! -f "$DCR_DEFINITION" ]]; then
    echo "DCR definition not found: $DCR_DEFINITION" >&2
    exit 1
fi

az account show --output none

if ! az rest \
    --method get \
    --url "https://management.azure.com${TABLE_ID}?api-version=${TABLE_API_VERSION}" \
    --output none 2>/dev/null; then
    echo "SAPOrca_CL does not exist. Run table-orca_add.sh first." >&2
    exit 1
fi

current_json="$(az rest \
    --method get \
    --url "https://management.azure.com${DCR_ID}?api-version=${DCR_API_VERSION}" \
    --output json)"

payload="$(jq --compact-output \
    --arg workspace_id "$WORKSPACE_ID" \
    --argjson current "$current_json" \
    '
    {
        location: $current.location,
        tags: ($current.tags // {}),
        properties: (
            .properties
            | .dataCollectionEndpointId = $current.properties.dataCollectionEndpointId
            | .destinations.logAnalytics |= map(
                if .name == "clv2ws1"
                then .workspaceResourceId = $workspace_id
                else .
                end
            )
        )
    }
    + if $current.kind != null then {kind: $current.kind} else {} end
    + if $current.identity != null then {identity: $current.identity} else {} end
    + if $current.sku != null then {sku: $current.sku} else {} end
    ' "$DCR_DEFINITION")"

if jq -e '.. | strings | select(test("\\{\\{.+\\}\\}"))' <<<"$payload" >/dev/null; then
    echo "Rendered DCR payload still contains an unresolved template placeholder." >&2
    exit 1
fi

echo "Updating Microsoft-Sentinel-SAPLogServ-DCR-79d7055b-44f..."
az rest \
    --method put \
    --url "https://management.azure.com${DCR_ID}?api-version=${DCR_API_VERSION}" \
    --headers "Content-Type=application/json" \
    --body "$payload" \
    --output none

provisioning_state="$(az rest \
    --method get \
    --url "https://management.azure.com${DCR_ID}?api-version=${DCR_API_VERSION}" \
    --query properties.provisioningState \
    --output tsv)"

echo "DCR provisioning state: ${provisioning_state:-unknown}"