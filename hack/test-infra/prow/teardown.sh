#!/bin/bash
set -eu

DIR="$(dirname "$0")"
SHARED_DIR="$DIR/../shared"

source "$SHARED_DIR/funcs.sh"
source "$DIR/vars"

kops_bin_ensure "$KOPS_VERSION"


$KOPS_BIN delete cluster \
    --name "${CLUSTER_NAME}" \
    --state "$KOPS_STATE_STORE" --yes


hostedzones="$(aws route53 list-hosted-zones-by-name --dns-name "$TOPDOMAIN" | jq -r '.HostedZones[]')"

parent_hostedzone="$(echo "$hostedzones" | jq "select(.Name == \"${TOPDOMAIN}.\")")"
parent_hostedzone_id=$(echo "$parent_hostedzone" | jq -r '.Id' | sed 's/\/hostedzone\///g')

subdomain_hostedzone="$(echo "$hostedzones" | jq "select(.Name == \"${SUBDOMAIN}.\")")"

if [ "" == "$subdomain_hostedzone" ]; then
    echo "HostedZone for \"$SUBDOMAIN\" does not exist. Skip deletion."
    exit 0
fi

ns_recordset=$(aws route53 list-resource-record-sets --hosted-zone-id "${parent_hostedzone_id}" \
    | jq ".ResourceRecordSets[] | select(.Type == \"NS\") | select(.Name == \"${SUBDOMAIN}.\")")

if [ "" == "${ns_recordset}" ]; then
    echo "NS record for '${SUBDOMAIN}' does not exist. Skip deleting."
else
    subdomain_ns_json=$(mktemp "${TEMPDIR:-/tmp}/${SUBDOMAIN}.NS.XXXXXX")
    cat > "$subdomain_ns_json" <<EOF
{
    "Comment": "Delete a subdomain NS record in the parent domain",
    "Changes": [{
        "Action": "DELETE",
        "ResourceRecordSet": $ns_recordset
    }]
}
EOF

    aws route53 change-resource-record-sets \
        --hosted-zone-id "$parent_hostedzone_id" \
        --change-batch "file://${subdomain_ns_json}" > /dev/null

    echo "NS record for '${SUBDOMAIN}' is deleted."
fi

aws s3 rm "${KOPS_STATE_STORE}" --recursive > /dev/null
