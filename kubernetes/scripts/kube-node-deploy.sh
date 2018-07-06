#!/bin/bash

set -e

# 创建缓存目录，在执行完成后，自动删除
TMPDIR=$(mktemp -d --tmpdir kubernetes_nodedeploy.XXXXXX)
trap 'rm -rf "${TMPDIR}"' EXIT
cd "${TMPDIR}" || exit

KUBE_VERSION="1.10.2"
KUBE_DOWNLOAD_URL="https://dl.k8s.io/v${KUBE_VERSION}/kubernetes-server-linux-amd64.tar.gz"
KUBE_HOST_IP=$(ifconfig ens3 |awk 'NR==2{print $2 }'|cut -d ":" -f2)
KUBE_HOST_NAME=$(cat /etc/hostname)
KUBE_CONF_DIR="/etc/kubernetes"
KUBE_CERT_DIR="/etc/kubernetes/pki"


CNI_PLUGIN_CALICO_VERSION="3.1.2"
CNI_PLUGIN_CALICO_URL="https://github.com/projectcalico/cni-plugin/releases/download/v${CNI_PLUGIN_CALICO_VERSION}/calico"
CNI_PLUGIN_CALICO_IPAM_URL="https://github.com/projectcalico/cni-plugin/releases/download/v${CNI_PLUGIN_CALICO_VERSION}/calico-ipam"
CNI_PLUGIN_BIN="/opt/cni/bin"

CNI_PLUGIN_VERSION="0.7.1"
CNI_PLUGIN_DOWNLOAD_URL="https://github.com/containernetworking/plugins/releases/download/v${CNI_PLUGIN_VERSION}/cni-plugins-amd64-v${CNI_PLUGIN_VERSION}.tgz"


# 下载安装 kube
function node_kube_bin() {
    wget ${KUBE_DOWNLOAD_URL} >/dev/null 2>&1
    tar -zxf kubernetes-server-linux-amd64.tar.gz
    cp -r kubernetes/server/bin/{kubelet,kube-proxy} /usr/local/bin/

    if [ ! -d "/var/lib/kubelet" ]; then
        mkdir /var/lib/kubelet
    fi
}

function cni_plugin()
{

    if [[ ! -d "${CNI_PLUGIN_BIN}" ]]; then
        mkdir -p "${CNI_PLUGIN_BIN}"
    fi

    curl -sSL -o "${CNI_PLUGIN_BIN}/calico" "${CNI_PLUGIN_CALICO_URL}"
    curl -sSL -o "${CNI_PLUGIN_BIN}/calico-ipam" "${CNI_PLUGIN_CALICO_IPAM_URL}"

    #下载其他cni组件
    wget "${CNI_PLUGIN_DOWNLOAD_URL}"
    tar zxf cni-plugins-amd64-v${CNI_PLUGIN_VERSION}}.tgz -C "${CNI_PLUGIN_BIN}"

    chmod 755 -R ${CNI_PLUGIN_BIN}/*
}

# 在node节点config配置文件需要注释掉KUBE_MASTER参数，否则会覆盖掉bootstrap.kubeconfig中的APISERVER地址
function modify_kubelet_config() {

    sed -i "s%KUBE_MASTER=\"--master=http:\/\/127.0.0.1:8080\"%# KUBE_MASTER=\"--master=http:\/\/127.0.0.1:8080\"%g" ${KUBE_CONF_DIR}/config

}


node_kube_bin
cni_plugin
modify_kubelet_config