#!/bin/bash

TMPDIR=$(mktemp -d --tmpdir etcd_install.XXXXXX)
trap 'rm -rf "${TMPDIR}"' EXIT
cd "${TMPDIR}" || exit

ETCD_VERSION="3.2.20"
ETCD_HOST_NAME=$(cat /etc/hostname)
ETCD_HOST_IP=$(ifconfig ens3 |awk 'NR==2{print $2 }'|cut -d ":" -f2)
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_CONF_DIR="/etc/etcd"
ETCD_CERT_DIR="/etc/kubernetes/pki/etcd"
ETCD_DOWNLOAD_URL="https://github.com/coreos/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz"

#下载 etcd
wget ${ETCD_DOWNLOAD_URL} >/dev/null 2>&1
tar -zxf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
cp etcd-v${ETCD_VERSION}-linux-amd64/etcd* /usr/local/bin

#创建etcd用户与用户组
getent group etcd >/dev/null || groupadd -r etcd
getent passwd etcd >/dev/null || useradd -r -g etcd -d /var/lib/etcd -s /sbin/nologin -c "etcd user" etcd

#创建etcd数据目录，并更改属主属组
if [ ! -d ${ETCD_DATA_DIR} ]; then
    mkdir /var/lib/etcd
    chown -R etcd:etcd ${ETCD_DATA_DIR}
fi

#创建etcd配置目录
if [ ! -d ${ETCD_CONF_DIR} ]; then
    mkdir -p ${ETCD_CONF_DIR}
fi

#创建etcd配置文件
cat <<EOF >  ${ETCD_CONF_DIR}/etcd.conf
# [member]
ETCD_NAME="${ETCD_HOST_NAME}"
ETCD_DATA_DIR="${ETCD_DATA_DIR}"
ETCD_LISTEN_PEER_URLS="https://${ETCD_HOST_IP}:2380"
ETCD_LISTEN_CLIENT_URLS="https://${ETCD_HOST_IP}:2379,https://127.0.0.1:2379"

# [clustering]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://${ETCD_HOST_IP}:2380"
ETCD_ADVERTISE_CLIENT_URLS="https://${ETCD_HOST_IP}:2379"
ETCD_INITIAL_CLUSTER="master-1=https://172.31.25.244:2380,master-2=https://172.31.29.234:2380,master-3=https://172.31.21.119:2380"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-token"
ETCD_INITIAL_CLUSTER_STATE="new"

# [security]
ETCD_CLIENT_CERT_AUTH="true"
ETCD_TRUSTED_CA_FILE="${ETCD_CERT_DIR}/ca.pem"
ETCD_CERT_FILE="${ETCD_CERT_DIR}/etcd.pem"
ETCD_KEY_FILE="${ETCD_CERT_DIR}/etcd-key.pem"
ETCD_PEER_CLIENT_CERT_AUTH="true"
ETCD_PEER_TRUSTED_CA_FILE="${ETCD_CERT_DIR}/ca.pem"
ETCD_PEER_CERT_FILE="${ETCD_CERT_DIR}/etcd.pem"
ETCD_PEER_KEY_FILE="${ETCD_CERT_DIR}/etcd-key.pem"
EOF

#创建 etcd systemd守护进程
cat <<EOF > /etc/systemd/system/etcd.service
[Unit]
Description=etcd server
After=network.target

[Service]
Type=notify
WorkingDirectory=${ETCD_DATA_DIR}
EnvironmentFile=-${ETCD_CONF_DIR}/etcd.conf
User=etcd
ExecStart=/usr/local/bin/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF