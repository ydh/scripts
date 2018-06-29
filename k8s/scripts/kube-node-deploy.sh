#!/bin/bash

KUBE_VERSION="1.10.2"
KUBE_DOWNLOAD_URL="https://dl.k8s.io/v${KUBE_VERSION}/kubernetes-server-linux-amd64.tar.gz"
KUBE_HOST_IP=$(ifconfig ens3 |awk 'NR==2{print $2 }'|cut -d ":" -f2)
KUBE_HOST_NAME=$(cat /etc/hostname)
KUBE_CONF_DIR="/etc/kubernetes"
KUBE_CERT_DIR="/etc/kubernetes/pki"
# 创建缓存目录，在执行完成后，自动删除
tmpdir=$(mktemp -d --tmpdir kubernetes_nodedeploy.XXXXXX)
trap 'rm -rf "${tmpdir}"' EXIT
cd "${tmpdir}" || exit

# 下载安装 kube
wget ${KUBE_DOWNLOAD_URL} >/dev/null 2>&1
tar -zxf kubernetes-server-linux-amd64.tar.gz
cp -r kubernetes/server/bin/{kubelet,kube-proxy} /usr/local/bin/

if [ ! -d "/var/lib/kubelet" ]; then
    mkdir /var/lib/kubelet
fi

#配置systemd守护进程
#kubelet.service
cat <<EOF > /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/var/lib/kubelet
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/kubelet
ExecStart=/usr/local/bin/kubelet \\
            \$KUBE_LOGTOSTDERR \\
            \$KUBE_LOG_LEVEL \\
            \$KUBELET_API_SERVER \\
            \$KUBELET_ADDRESS \\
            \$KUBELET_PORT \\
            \$KUBELET_HOSTNAME \\
            \$KUBE_ALLOW_PRIV \\
            \$KUBELET_ARGS
Restart=on-failure
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

#kube-proxy.service
cat <<EOF > /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/proxy
ExecStart=/usr/local/bin/kube-proxy \\
            \$KUBE_LOGTOSTDERR \\
            \$KUBE_LOG_LEVEL \\
            \$KUBE_MASTER \\
            \$KUBE_PROXY_ARGS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

#node节点所需配置文件
cat<<EOF > /etc/kubernetes/config
###
# kubernetes system config
#
# The following values are used to configure various aspects of all
# kubernetes services, including
#
#   kube-apiserver.service
#   kube-controller-manager.service
#   kube-scheduler.service
#   kubelet.service
#   kube-proxy.service
# logging to stderr means we get it in the systemd journal
KUBE_LOGTOSTDERR="--logtostderr=true"

# journal message level, 0 is debug
KUBE_LOG_LEVEL="--v=2"

# Should this cluster be allowed to run privileged docker containers
KUBE_ALLOW_PRIV="--allow-privileged=true"

# How the controller-manager, scheduler, and proxy find the apiserver
# KUBE_MASTER="--master=http://127.0.0.1:8080"
EOF

# kubeket 默认也开启了证书轮换能力以保证自动续签相关证书，同时增加了 --node-labels 选项为 node 打一个标签，关于这个标签最后部分会有讨论，如果在 master 上启动 kubelet，请将 node-role.kubernetes.io/k8s-node=true 修改为 node-role.kubernetes.io/k8s-master=true
cat <<EOF > /etc/kubernetes/kubelet
###
# kubernetes kubelet (minion) config

# The address for the info server to serve on (set to 0.0.0.0 or "" for all interfaces)
KUBELET_ADDRESS="--node-ip=${KUBE_HOST_IP}"

# The port for the info server to serve on
# KUBELET_PORT="--port=10250"

# You may leave this blank to use the actual hostname
KUBELET_HOSTNAME="--hostname-override=${KUBE_HOST_NAME}"

# location of the api-server
# KUBELET_API_SERVER=""

# Add your own!
KUBELET_ARGS="  --bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \\
                --cert-dir=/etc/kubernetes/pki \\
                --cgroup-driver=cgroupfs \\
                --cluster-dns=10.254.0.2 \\
                --cluster-domain=cluster.local \\
                --fail-swap-on=false \\
                --hairpin-mode promiscuous-bridge \\
                --feature-gates=RotateKubeletClientCertificate=true,RotateKubeletServerCertificate=true \\
                --node-labels=node-role.kubernetes.io/k8s-node=true \\
                --image-gc-high-threshold=75 \\
                --image-gc-low-threshold=60 \\
                --kube-reserved=cpu=500m,memory=512Mi,ephemeral-storage=1Gi \\
                --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \\
                --system-reserved=cpu=1000m,memory=1024Mi,ephemeral-storage=1Gi \\
                --serialize-image-pulls=false \\
                --sync-frequency=30s \\
                --pod-infra-container-image=k8s.gcr.io/pause-amd64:3.1 \\
                --resolv-conf=/etc/resolv.conf \\
                --rotate-certificates"
EOF

cat <<EOF > /etc/kubernetes/proxy
###
# kubernetes proxy config
# default config should be adequate
# Add your own!
KUBE_PROXY_ARGS="   --bind-address=0.0.0.0 \\
                    --hostname-override=${KUBE_HOST_NAME} \\
                    --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig \\
                    --cluster-cidr=10.10.0.0/16"
#                    --masquerade-all \\
#                    --proxy-mode=ipvs \\
#                    --ipvs-min-sync-period=5s \\
#                    --ipvs-sync-period=5s \\
#                    --ipvs-scheduler=rr"
EOF