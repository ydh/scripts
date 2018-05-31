#!/bin/bash

TMPDIR=$(mktemp -d --tmpdir calico_cni_nodedeploy.XXXXXX)
trap 'rm -rf "${TMPDIR}"' EXIT
cd "${TMPDIR}" || exit

CNI_PLUGIN_VERSION="3.1.2"
CNI_PLUGIN_CALICO_URL="https://github.com/projectcalico/cni-plugin/releases/download/v${CNI_PLUGIN_VERSION}/calico"
CNI_PLUGIN_CALICO_IPAM_URL="https://github.com/projectcalico/cni-plugin/releases/download/v${CNI_PLUGIN_VERSION}/calico-ipam"

CNI_PLUGIN_BIN="/opt/cni/bin"

if [[ ! -d "${CNI_PLUGIN_BIN}" ]]; then
    mkdir -p "${CNI_PLUGIN_BIN}"
fi

# 下载安装 kub
curl -sSL -o "${CNI_PLUGIN_BIN}/calico" "${CNI_PLUGIN_CALICO_URL}"
curl -sSL -o "${CNI_PLUGIN_BIN}/calico-ipam" "${CNI_PLUGIN_CALICO_IPAM_URL}"
chmod 755 -R ${CNI_PLUGIN_BIN}/*