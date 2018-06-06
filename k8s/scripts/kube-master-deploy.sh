#!/bin/bash

KUBE_VERSION="1.10.2"
KUBE_DOWNLOAD_URL="https://dl.k8s.io/v${KUBE_VERSION}/kubernetes-server-linux-amd64.tar.gz"
KUBE_HOST_IP=$(ifconfig ens3 |awk 'NR==2{print $2 }'|cut -d ":" -f2)
KUBE_CONF_DIR="/etc/kubernetes"
KUBE_CERT_DIR="/etc/kubernetes/pki"
ETCD_CERT_DIR="/etc/kubernetes/pki/etcd"

# 创建缓存目录，在执行完成后，自动删除
tmpdir=$(mktemp -d --tmpdir kubernetes_masterdeploy.XXXXXX)
trap 'rm -rf "${tmpdir}"' EXIT
cd "${tmpdir}" || exit

# 下载安装 kube
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

# master节点kube-apiserver、kube-controller-manager、kube-scheduler组件 systemd守护进程
#kube-apiserver.service
cat<<EOF > /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target
After=etcd.service

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/apiserver
User=kube
ExecStart=/usr/local/bin/kube-apiserver \\
            \$KUBE_LOGTOSTDERR \\
            \$KUBE_LOG_LEVEL \\
            \$KUBE_ETCD_SERVERS \\
            \$KUBE_API_ADDRESS \\
            \$KUBE_API_PORT \\
            \$KUBELET_PORT \\
            \$KUBE_ALLOW_PRIV \\
            \$KUBE_SERVICE_ADDRESSES \\
            \$KUBE_ADMISSION_CONTROL \\
            \$KUBE_API_ARGS
Restart=on-failure
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

#kube-controller-manager.service
cat <<EOF > /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/controller-manager
User=kube
ExecStart=/usr/local/bin/kube-controller-manager \\
            \$KUBE_LOGTOSTDERR \\
            \$KUBE_LOG_LEVEL \\
            \$KUBE_MASTER \\
            \$KUBE_CONTROLLER_MANAGER_ARGS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

#kube-scheduler.service
cat <<EOF > /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler Plugin
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/scheduler
User=kube
ExecStart=/usr/local/bin/kube-scheduler \\
            \$KUBE_LOGTOSTDERR \\
            \$KUBE_LOG_LEVEL \\
            \$KUBE_MASTER \\
            \$KUBE_SCHEDULER_ARGS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# master节点所需配置文件
# config
# config 是一个通用配置文件，值得注意的是由于安装时对于 Node、Master 节点都会包含该文件，在 Node 节点上请注释掉 KUBE_MASTER 变量，因为 Node 节点需要做 HA，要连接本地的 6443 加密端口；而这个变量将会覆盖 kubeconfig 中指定的 127.0.0.1:6443 地址
cat <<EOF > ${KUBE_CONF_DIR}/config
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
KUBE_MASTER="--master=http://127.0.0.1:8080"
EOF

# apiserver
# apiserver 配置相对于 1.8 略有变动，其中准入控制器(admission control)选项名称变为了 --enable-admission-plugins，控制器列表也有相应变化，这里采用官方推荐配置，具体请参考https://kubernetes.io/docs/admin/admission-controllers/#is-there-a-recommended-set-of-admission-controllers-to-use
cat <<EOF > ${KUBE_CONF_DIR}/apiserver
###
# kubernetes system config
#
# The following values are used to configure the kube-apiserver
#

# The address on the local server to listen to.
KUBE_API_ADDRESS="--advertise-address=${KUBE_HOST_IP} --bind-address=${KUBE_HOST_IP}"

# The port on the local server to listen on.
KUBE_API_PORT="--secure-port=6443"

# Port minions listen on
# KUBELET_PORT="--kubelet-port=10250"

# Comma separated list of nodes in the etcd cluster
KUBE_ETCD_SERVERS="--etcd-servers=https://172.31.25.244:2379,master-2=https://172.31.29.234:2379,master-3=https://172.31.21.119:2379"

# Address range to use for services
KUBE_SERVICE_ADDRESSES="--service-cluster-ip-range=10.254.0.0/16"

# default admission control policies
KUBE_ADMISSION_CONTROL="--enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota,NodeRestriction"

# Add your own!
KUBE_API_ARGS=" --anonymous-auth=false \\
                --apiserver-count=3 \\
                --audit-log-maxage=30 \\
                --audit-log-maxbackup=3 \\
                --audit-log-maxsize=100 \\
                --audit-log-path=/var/log/kube-audit/audit.log \\
                --audit-policy-file=/etc/kubernetes/audit-policy.yaml \\
                --authorization-mode=Node,RBAC \\
                --client-ca-file=/etc/kubernetes/pki/ca.pem \\
                --enable-bootstrap-token-auth \\
                --enable-garbage-collector \\
                --enable-logs-handler \\
                --enable-swagger-ui \\
                --etcd-cafile=/etc/kubernetes/pki/etcd/ca.pem \\
                --etcd-certfile=/etc/kubernetes/pki/etcd/etcd.pem \\
                --etcd-keyfile=/etc/kubernetes/pki/etcd/etcd-key.pem \\
                --etcd-compaction-interval=5m0s \\
                --etcd-count-metric-poll-period=1m0s \\
                --event-ttl=48h0m0s \\
                --kubelet-https=true \\
                --kubelet-timeout=3s \\
                --log-flush-frequency=5s \\
                --token-auth-file=/etc/kubernetes/token.csv \\
                --tls-cert-file=/etc/kubernetes/pki/kube-apiserver.pem \\
                --tls-private-key-file=/etc/kubernetes/pki/kube-apiserver-key.pem \\
                --service-node-port-range=30000-32767 \\
                --service-account-key-file=/etc/kubernetes/pki/ca-key.pem \\
                --storage-backend=etcd3 \\
                --requestheader-client-ca-file=/etc/kubernetes/pki/ca.pem \\
                --proxy-client-cert-file=/etc/kubernetes/pki/kube-proxy.pem \\
                --proxy-client-key-file=/etc/kubernetes/pki/kube-proxy-key.pem \\
                --requestheader-allowed-names=aggregator \\
                --requestheader-extra-headers-prefix=X-Remote-Extra- \\
                --requestheader-group-headers=X-Remote-Group \\
                --requestheader-username-headers=X-Remote-User \\
                --enable-aggregator-routing=true \\
                --enable-swagger-ui=true"
EOF

# controller manager
# controller manager 配置默认开启了证书轮换能力用于自动签署 kueblet 证书，并且证书时间也设置了 10 年，可自行调整；增加了 --controllers 选项以指定开启全部控制器
cat <<EOF > ${KUBE_CONF_DIR}/controller-manager
###
# The following values are used to configure the kubernetes controller-manager

# defaults from config and apiserver should be adequate

# Add your own!
KUBE_CONTROLLER_MANAGER_ARGS="  --bind-address=0.0.0.0 \\
                                --service-cluster-ip-range=10.254.0.0/16 \\
                                --cluster-cidr=10.10.0.0/16 \\
                                --allocate-node-cidrs=true \\
                                --cluster-name=kubernetes \\
                                --cluster-signing-cert-file=/etc/kubernetes/pki/ca.pem \\
                                --cluster-signing-key-file=/etc/kubernetes/pki/ca-key.pem \\
                                --controllers=*,bootstrapsigner,tokencleaner \\
                                --deployment-controller-sync-period=10s \\
                                --experimental-cluster-signing-duration=86700h0m0s \\
                                --leader-elect=true \\
                                --node-monitor-grace-period=40s \\
                                --node-monitor-period=5s \\
                                --pod-eviction-timeout=5m0s \\
                                --terminated-pod-gc-threshold=50 \\
                                --root-ca-file=/etc/kubernetes/pki/ca.pem \\
                                --service-account-private-key-file=/etc/kubernetes/pki/ca-key.pem \\
                                --feature-gates=RotateKubeletServerCertificate=true"
EOF

# scheduler
cat <<EOF > ${KUBE_CONF_DIR}/scheduler
###
# kubernetes scheduler config

# default config should be adequate

# Add your own!
KUBE_SCHEDULER_ARGS="   --address=0.0.0.0 \\
                        --leader-elect=true \\
                        --algorithm-provider=DefaultProvider"
EOF