#!/bin/bash

function kops_bin_ensure {
    _expected_version="$1"
    _kops_versioned_bin="kops${_expected_version}"

    if ! command -v "$_kops_versioned_bin" > /dev/null; then
        if command -v kops > /dev/null && [ "$(kops version | cut -d ' ' -f2)" == "$_expected_version" ]; then
            # shellcheck disable=SC2230
            ln -s "$(which kops)" "./bin/kops${_expected_version}"
        else
            kops_bin_download "$_expected_version"
        fi
    fi
}


function kops_bin_download {
    _expected_version="$1"

    _url="https://github.com/kubernetes/kops/releases/download/v${_expected_version}/kops-darwin-amd64"
    wget -O "./bin/kops${_expected_version}" "$_url"
    chmod +x "./bin/kops${_expected_version}"
}

function aws_state_bucket_ensure_exists {
    _kops_state_bucket_name="$1"

    if aws s3 ls "s3://$_kops_state_bucket_name" 2>&1 | grep -q 'NoSuchBucket'; then
        aws s3api create-bucket --bucket "$_kops_state_bucket_name" --region us-east-1 > /dev/null

        aws s3api put-bucket-versioning --bucket "$_kops_state_bucket_name" \
            --versioning-configuration Status=Enabled > /dev/null

        aws s3api put-bucket-encryption --bucket "$_kops_state_bucket_name" \
            --server-side-encryption-configuration \
            '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' > /dev/null

        echo "KOPS state bucket '${_kops_state_bucket_name}' created."
    else
        echo "KOPS state bucket '${_kops_state_bucket_name}' exists. Skip creating."
    fi
}
