#!/bin/bash

# 创建缓存目录，在执行完成后，自动删除
TMPDIR=$(mktemp -d --tmpdir kubernetes_kubeconfig.XXXXXX)
trap 'rm -rf "${TMPDIR}"' EXIT
cd "${TMPDIR}" || exit

kubeconfig_dir="/tmp/kubernetes"
KUBE_VERSION="1.10.2"
KUBE_DOWNLOAD_URL="https://dl.k8s.io/v${KUBE_VERSION}/kubernetes-server-linux-amd64.tar.gz"

# 下载kubectl
wget ${KUBE_DOWNLOAD_URL} >/dev/null 2>&1
tar -zxf kubernetes-server-linux-amd64.tar.gz
chmod +x ./kubernetes/server/bin/kubectl
export PATH="$PATH:${TMPDIR}/kubernetes/server/bin/"

# 生成kube_config 配置文件
# 地址默认为 127.0.0.1:6443
# 如果在 master 上启用 kubelet 请在生成后的 kubeconfig 中
# 修改该地址为 当前MASTER_IP:6443

KUBE_APISERVER="https://127.0.0.1:6443"
BOOTSTRAP_TOKEN=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
echo "Tokne: ${BOOTSTRAP_TOKEN}"

cat > token.csv <<EOF
${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,"system:bootstrappers"
EOF

echo "Create kubelet bootstrapping kubeconfig..."
# 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=${kubeconfig_dir}/pki/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=bootstrap.kubeconfig
# 设置客户端认证参数
kubectl config set-credentials kubelet-bootstrap \
  --token=${BOOTSTRAP_TOKEN} \
  --kubeconfig=bootstrap.kubeconfig
# 设置上下文参数
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kubelet-bootstrap \
  --kubeconfig=bootstrap.kubeconfig
# 设置默认上下文
kubectl config use-context default --kubeconfig=bootstrap.kubeconfig

echo "Create kube-proxy kubeconfig..."
# 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=${kubeconfig_dir}/pki/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-proxy.kubeconfig
# 设置客户端认证参数
kubectl config set-credentials kube-proxy \
  --client-certificate=${kubeconfig_dir}/pki/kube-proxy.pem \
  --client-key=${kubeconfig_dir}/pki/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
# 设置上下文参数
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
# 设置默认上下文
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

# 创建高级审计配置
cat >> audit-policy.yaml <<EOF
# Log all requests at the Metadata level.
apiVersion: audit.k8s.io/v1beta1
kind: Policy
rules:
- level: Metadata
EOF

cp ./bootstrap.kubeconfig ${kubeconfig_dir}
cp ./kube-proxy.kubeconfig ${kubeconfig_dir}
cp ./audit-policy.yaml ${kubeconfig_dir}
cp ./token.csv ${kubeconfig_dir}