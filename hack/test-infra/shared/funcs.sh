#!/bin/bash

function kops_bin_ensure {
    _expected_version="$1"
    _kops_versioned_bin="kops${_expected_version}"

    if ! command -v "$_kops_versioned_bin" > /dev/null; then
        if command -v kops > /dev/null && [ "$(kops version | cut -d ' ' -f2)" == "$_expected_version" ]; then
            # shellcheck disable=SC2230
            cp "$(which kops)" "./bin/kops${_expected_version}"
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
