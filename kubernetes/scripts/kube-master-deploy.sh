#!/bin/bash

set -e

# 创建缓存目录，在执行完成后，自动删除
TMPDIR=$(mktemp -d --tmpdir kubernetes_masterdeploy.XXXXXX)
trap 'rm -rf "${TMPDIR}"' EXIT
cd "${TMPDIR}" || exit

KUBE_VERSION="1.10.2"
KUBE_DOWNLOAD_URL="https://dl.k8s.io/v${KUBE_VERSION}/kubernetes-server-linux-amd64.tar.gz"
KUBE_HOST_IP=$(ifconfig ens3 |awk 'NR==2{print $2 }'|cut -d ":" -f2)
KUBE_CONF_DIR="/etc/kubernetes"

ETCD_SERVERS="https://172.31.25.244:2379,master-2=https://172.31.29.234:2379,master-3=https://172.31.21.119:2379"

# 下载安装 kube
function master_kube_bin() {
    wget ${KUBE_DOWNLOAD_URL} >/dev/null 2>&1
    tar -zxf kubernetes-server-linux-amd64.tar.gz
    cp -r kubernetes/server/bin/{kube-apiserver,kube-controller-manager,kube-scheduler,kubectl,kubelet,kube-proxy} /usr/local/bin/

    # 创建 kube用户 master节点需要此用户(为了安全)，node节点不需要
    getent group kube >/dev/null || groupadd -r kube
    getent passwd kube >/dev/null || useradd -r -g kube -d / -s /sbin/nologin -c "Kubernetes user" kube

    if [ ! -d "/var/log/kube-audit" ]; then
        mkdir /var/log/kube-audit
    fi

    chown -R kube:kube /var/log/kube-audit
}

#替换不同主机配置文件参数
function modify_apiserver_config() {

    sed -i "s#KUBE_API_ADDRESS=\"--advertise-address=127.0.0.1 --bind-address=127.0.0.1\"#KUBE_API_ADDRESS=\"--advertise-address=${KUBE_HOST_IP} --bind-address=${KUBE_HOST_IP}\"#g" ${KUBE_CONF_DIR}/apiserver

    sed -i "s#KUBE_ETCD_SERVERS=\"--etcd-servers=https:\/\/127.0.0.1:2379\"#KUBE_ETCD_SERVERS=\"--etcd-servers=${ETCD_SERVERS}\"#g" ${KUBE_CONFIG_DIR}/apiserver

}

master_kube_bin
modify_apiserver_config