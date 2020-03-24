#!/bin/bash
set -eu

DIR="$(dirname "$0")"
SHARED_DIR="$DIR/../shared"

source "$SHARED_DIR/funcs.sh"
source "$DIR/vars"

kops_bin_ensure "$KOPS_VERSION"

################################################################################
############################# INFRA PREPRATION #################################
################################################################################

hostedzones="$(aws route53 list-hosted-zones-by-name --dns-name "$TOPDOMAIN" | jq -r '.HostedZones[]')"

parent_hostedzone="$(echo "$hostedzones" | jq "select(.Name == \"${TOPDOMAIN}.\")")"
parent_hostedzone_id=$(echo "$parent_hostedzone" | jq -r '.Id' | sed 's/\/hostedzone\///g')

subdomain_hostedzone="$(echo "$hostedzones" | jq "select(.Name == \"${SUBDOMAIN}.\")")"

if [ "" == "$subdomain_hostedzone" ]; then
    subdomain_hostedzone=$(aws route53 create-hosted-zone \
        --name "$SUBDOMAIN" \
        --caller-reference "$(uuidgen)" \
        --hosted-zone-config Comment="$SUBDOMAIN")
    echo "HostedZone for \"$SUBDOMAIN\" is created."
else
    echo "Hosted Zone for '$SUBDOMAIN' exists. Skip creating."
fi

subdomain_hostedzone_id=$(echo "$subdomain_hostedzone" | jq -r '.Id' | sed 's/\/hostedzone\///g')
subdomain_hostedzone_deligationset=$(aws route53 get-hosted-zone --id "$subdomain_hostedzone_id" | jq '.DelegationSet')

ns1=$(echo "$subdomain_hostedzone_deligationset" | jq -r '.NameServers[0]')
ns2=$(echo "$subdomain_hostedzone_deligationset" | jq -r '.NameServers[1]')
ns3=$(echo "$subdomain_hostedzone_deligationset" | jq -r '.NameServers[2]')
ns4=$(echo "$subdomain_hostedzone_deligationset" | jq -r '.NameServers[3]')

subdomain_ns_json=$(mktemp "${TEMPDIR:-/tmp}/${SUBDOMAIN}.NS.XXXXXX")
cat > "$subdomain_ns_json" <<EOF
{
    "Comment": "Create a subdomain NS record in the parent domain",
    "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
            "Name": "${SUBDOMAIN}",
            "Type": "NS",
            "TTL": 300,
            "ResourceRecords": [{
                    "Value": "${ns1}."
                }, {
                    "Value": "${ns2}."
                }, {
                    "Value": "${ns3}."
                }, {
                    "Value": "${ns4}."
                }
            ]
        }
    }]
}
EOF

aws route53 change-resource-record-sets \
    --hosted-zone-id "$parent_hostedzone_id" \
    --change-batch "file://${subdomain_ns_json}" > /dev/null

echo "NS record for '${SUBDOMAIN}' is created / updated."

if aws s3 ls "s3://$KOPS_STATE_BUCKET_NAME" 2>&1 | grep -q 'NoSuchBucket'; then
    aws s3api create-bucket --bucket "$KOPS_STATE_BUCKET_NAME" --region us-east-1 > /dev/null

    aws s3api put-bucket-versioning --bucket "$KOPS_STATE_BUCKET_NAME" \
        --versioning-configuration Status=Enabled > /dev/null

    aws s3api put-bucket-encryption --bucket "$KOPS_STATE_BUCKET_NAME" \
        --server-side-encryption-configuration \
        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' > /dev/null

    echo "KOPS state bucket '${KOPS_STATE_BUCKET_NAME}' created."
else
    echo "KOPS state bucket '${KOPS_STATE_BUCKET_NAME}' exists. Skip creating."
fi


################################################################################
################################ KOPS CONFIG ###################################
################################################################################


# aws ec2 describe-availability-zones --region ap-southeast-2
KOPS_RUN_OBSOLETE_VERSION=1 \
$KOPS_BIN create cluster \
    --zones ap-southeast-2c \
    --name "${CLUSTER_NAME}" \
    --state "$KOPS_STATE_STORE" \
    --ssh-public-key "$SHARED_DIR/id_rsa.pub" \
    --kubernetes-version "${KUBERNETES_VERSION}" \
    --yes


# while [ 1 ]; do
#     $KOPS_BIN validate cluster --name ${CLUSTER_NAME} --state "$KOPS_STATE_STORE" && break || sleep 30
# done;
