#!/bin/bash
set -eu

DIR="$(dirname "$0")"
SHARED_DIR="$DIR/../shared"

source "$SHARED_DIR/funcs.sh"
source "$DIR/vars"

function main {
    clusterrolebinding_ensure
    secret_hmactoken_ensure
    secret_oauthtoken_ensure
    setup_ingress_controller
    reconcile_webhook
    setup_prow
}

function clusterrolebinding_ensure {
    set +e
    $KUBECTL_BIN get clusterrolebinding cluster-admin-binding-"${PROW_USER}" > /dev/null 2>&1
    if [ "0" != "$?" ]; then
        $KUBECTL_BIN create clusterrolebinding \
            cluster-admin-binding-"${PROW_USER}" \
            --clusterrole=cluster-admin --user="${PROW_USER}"
    fi
    set -e
}

function secret_hmactoken_ensure {
    set +e
    $KUBECTL_BIN get secret hmac-token > /dev/null 2>&1
    if [ "0" != "$?" ]; then
        $KUBECTL_BIN create secret generic hmac-token \
            --from-literal=hmac="${GITHUB_HOOK_SECRET}"
    fi
    set -e
}

function secret_oauthtoken_ensure {
    set +e
    $KUBECTL_BIN get secret oauth-token > /dev/null 2>&1
    if [ "0" != "$?" ]; then
        $KUBECTL_BIN create secret generic oauth-token \
            --from-literal=oauth="${GITHUB_PROW_BOT_ACCESS_TOKEN}"
    fi
    set -e
}

function setup_ingress_controller {
    $KUBECTL_BIN apply -f \
        https://raw.githubusercontent.com/mousavian/kops/master/addons/ingress-nginx/v1.6.0.yaml

    lb_address="$($KUBECTL_BIN get ing/ing -o json | jq -r '.status.loadBalancer.ingress[0].hostname')"
    lb_hosteedzone="$(aws elb describe-load-balancers \
        | jq -r ".LoadBalancerDescriptions[] | select(.DNSName == \"${lb_address}\") | .CanonicalHostedZoneNameID")"

    subdomain_hostedzone_id="$(aws route53 list-hosted-zones-by-name --dns-name "$SUBDOMAIN" \
        | jq -r ".HostedZones[] | select(.Name == \"${SUBDOMAIN}.\") | .Id" \
        | sed 's/\/hostedzone\///g')"

    subdomain_ns_json=$(mktemp "${TEMPDIR:-/tmp}/${SUBDOMAIN}.NS.XXXXXX")
cat > "$subdomain_ns_json" <<EOF
{
    "Comment": "Create a subdomain NS record in the parent domain",
    "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
            "Name": "web.${SUBDOMAIN}",
            "Type": "A",
            "AliasTarget": {
                "HostedZoneId": "${lb_hosteedzone}",
                "DNSName": "dualstack.${lb_address}",
                "EvaluateTargetHealth": false
            }
        }
    }]
}
EOF
    aws route53 change-resource-record-sets \
        --hosted-zone-id "$subdomain_hostedzone_id" \
        --change-batch "file://${subdomain_ns_json}" > /dev/null
}

function reconcile_webhook {
    _webhook_url="https://web.${SUBDOMAIN}/hook"

    set +e
    curl -s -XGET https://api.github.com/repos/mousavian/mysql-operator/hooks \
        -H "Content-Type: application/json" \
        -H "Authorization: token ${GITHUB_REPO_WEBHOOK_ACCESS_TOKEN}" \
        | jq -e ".[] | select (.config.url == \"${_webhook_url}\")" > /dev/null 2>&1
    _exit_code="$?"
    set -e

    if [ "0" != "$_exit_code" ]; then
        webhook_json=$(mktemp "${TEMPDIR:-/tmp}/web.${SUBDOMAIN}.webhook.XXXXXX")
cat > "$webhook_json" <<EOF
{
    "name": "web",
    "active": true,
    "events": ["*"],
    "config": {
        "secret": "${GITHUB_HOOK_SECRET}",
        "url": "${_webhook_url}",
        "insecure_ssl": "1",
        "content_type": "json"
    }
}
EOF

        curl -s https://api.github.com/repos/mousavian/mysql-operator/hooks \
            -H "Content-Type: application/json" \
            -H "Authorization: token ${GITHUB_REPO_WEBHOOK_ACCESS_TOKEN}" \
            -X POST \
            -d "@${webhook_json}"
    fi
}

function setup_prow {
    $KUBECTL_BIN apply -f \
        https://raw.githubusercontent.com/kubernetes/test-infra/master/prow/cluster/starter.yaml

    $KUBECTL_BIN create configmap plugins \
        --from-file=plugins.yaml=.prow/plugins.yaml --dry-run -o yaml \
        | $KUBECTL_BIN replace configmap plugins -f -

    $KUBECTL_BIN create configmap config \
        --from-file=config.yaml=.prow/config.yaml --dry-run -o yaml \
        | $KUBECTL_BIN replace configmap config -f -
}

main
