#!/bin/bash
set -eu

DIR="$(dirname "$0")"
SHARED_DIR="$DIR/../shared"

source "$SHARED_DIR/funcs.sh"
source "$DIR/vars"

kops_bin_ensure "$KOPS_VERSION"

$KOPS_BIN validate cluster \
    --name "${CLUSTER_NAME}" \
    --state "$KOPS_STATE_STORE"
