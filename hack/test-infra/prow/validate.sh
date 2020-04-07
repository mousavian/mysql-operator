#!/bin/bash
set -eu

DIR="$(dirname "$0")"
SHARED_DIR="$DIR/../shared"

source "$SHARED_DIR/funcs.sh"
source "$DIR/vars"

kops_bin_ensure "$KOPS_VERSION"

CLUSTER_READINESS="1"

while [ "1" == "${CLUSTER_READINESS}" ]; do
    printf "[$(date +%H:%M:%S)] Cluster is "

    $KOPS_BIN validate cluster \
        --name "${CLUSTER_NAME}" \
        --state "$KOPS_STATE_STORE" > /dev/null 2>&1

    CLUSTER_READINESS="$?"

    if [ "1" == "${CLUSTER_READINESS}" ]; then
        echo "NOT ready yet"
        sleep 5
    else
        echo "READY"
    fi
done
