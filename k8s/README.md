# 脚本与文档逐步完善中……
**PS:请不要吐槽我的脚本和文档垃圾，能力有限，就只能写成这样了。**

# system config
```bash
#集群所有节点system配置
ansible -i ./k8s/hosts.ini k8s-cluster -m script -a "./k8s/scripts/system.sh"
```

# docker deploy
```bash
ansible -i ./k8s/hosts.ini kube-node -m script -a "./k8s/scripts/docker-deploy.sh"
```

# 集群所需证书与kubeconfig文件
## 在ansible节点执行`make-etcd-cert.sh`,`make-kube-cert.sh`,`make-kube-conf.sh`
```bash
#注意修改脚本文件中的etcd主机的ip
sh ./k8s/scripts/make-etcd-cert.sh
sh ./k8s/scripts/make-kube-cert.sh
sh ./k8s/scripts/make-kube-conf.sh
#脚本执行完成后，证书与配置文件存放在`/tmp/kubernetes/`
[root@ansible ~]# tree /tmp/kubernetes/
/tmp/kubernetes/
├── audit-policy.yaml
├── bootstrap.kubeconfig
├── kube-proxy.kubeconfig
├── pki
│   ├── admin-key.pem
│   ├── admin.pem
│   ├── ca-key.pem
│   ├── ca.pem
│   ├── etcd
│   │   ├── ca-key.pem
│   │   ├── ca.pem
│   │   ├── etcd-key.pem
│   │   └── etcd.pem
│   ├── kube-apiserver-key.pem
│   ├── kube-apiserver.pem
│   ├── kube-proxy-key.pem
│   └── kube-proxy.pem
└── token.csv

2 directories, 16 files
```

## copy配置文件与证书到所有节点
```bash
ansible -i ./k8s/hosts.ini k8s-cluster -m copy -a "src=/tmp/kubernetes/  dest=/etc/kubernetes"
```

# etcd-deploy
## 通过ansible script模块在etcd节点执行etcd-deploy.sh
```bash
#部署etcd
ansible -i ./k8s/hosts.ini etcd -m script -a "./k8s/scripts/etcd-deploy.sh"

# 启动etcd
ansible -i ./k8s/hosts.ini etcd -m shell -a "systemctl daemon-reload"
ansible -i ./k8s/hosts.ini etcd -m shell -a "systemctl start etcd"
ansible -i ./k8s/hosts.ini etcd -m shell -a "systemctl enable etcd"

#查看节点健康状态
ansible -i ./k8s/hosts.ini etcd -m shell -a 'etcdctl --ca-file=/etc/kubernetes/pki/etcd/ca.pem --cert-file=/etc/kubernetes/pki/etcd/etcd.pem --key-file=/etc/kubernetes/pki/etcd/etcd-key.pem  --endpoints=https://172.31.25.244:2379,https://172.31.29.234:2379,https://172.31.21.119:2379 cluster-health'
```

# kube-master-deploy
```bash
ansible -i ./k8s/hosts.ini kube-master -m script -a "./k8s/scripts/kube-master-deploy.sh"

#启动master节点
ansible -i ./k8s/hosts.ini kube-master -m shell -a "systemctl daemon-reload"
ansible -i ./k8s/hosts.ini kube-master -m shell -a "systemctl start kube-apiserver"
ansible -i ./k8s/hosts.ini kube-master -m shell -a "systemctl start kube-controller-manager"
ansible -i ./k8s/hosts.ini kube-master -m shell -a "systemctl start kube-scheduler"
ansible -i ./k8s/hosts.ini kube-master -m shell -a "systemctl enable kube-apiserver"
ansible -i ./k8s/hosts.ini kube-master -m shell -a "systemctl enable kube-controller-manager"
ansible -i ./k8s/hosts.ini kube-master -m shell -a "systemctl enable kube-scheduler"

# 查看master服务状态
ansible -i ./k8s/hosts.ini kube-master -m shell -a "kubectl get componentstatuses"
```

# kube-node-deploy
## 部署
```bash
ansible -i ./k8s/hosts.ini kube-node -m script -a "./k8s/scripts/kube-node-deploy.sh"
```

## 在 aws 创建私有ELB反向代理master节点的6443端口

## TLS bootstrapping （手动在任意master节点执行  ）
创建好 ELB 后不要忘记为 TLS Bootstrap 创建相应的 RBAC 规则，这些规则能实现证自动签署 TLS Bootstrap 发出的 CSR 请求，从而实现证书轮换(创建一次即可)；参考：https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet-tls-bootstrapping/
tls-bootstrapping-clusterrole.yaml
```bash
cat <<EOF > tls-bootstrapping-clusterrole.yaml
# A ClusterRole which instructs the CSR approver to approve a node requesting a
# serving cert matching its client cert.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: system:certificates.k8s.io:certificatesigningrequests:selfnodeserver
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeserver"]
  verbs: ["create"]
EOF
```

## 在master上执行
```bash

# 给与 kubelet-bootstrap 用户进行 node-bootstrapper 的权限
kubectl create clusterrolebinding kubelet-bootstrap \
    --clusterrole=system:node-bootstrapper \
    --user=kubelet-bootstrap

kubectl create -f tls-bootstrapping-clusterrole.yaml

# 自动批准 system:bootstrappers 组用户 TLS bootstrapping 首次申请证书的 CSR 请求
kubectl create clusterrolebinding node-client-auto-approve-csr \
        --clusterrole=system:certificates.k8s.io:certificatesigningrequests:nodeclient \
        --group=system:bootstrappers

# 自动批准 system:nodes 组用户更新 kubelet 自身与 apiserver 通讯证书的 CSR 请求
kubectl create clusterrolebinding node-client-auto-renew-crt \
        --clusterrole=system:certificates.k8s.io:certificatesigningrequests:selfnodeclient \
        --group=system:nodes

# 自动批准 system:nodes 组用户更新 kubelet 10250 api 端口证书的 CSR 请求
kubectl create clusterrolebinding node-server-auto-renew-crt \
        --clusterrole=system:certificates.k8s.io:certificatesigningrequests:selfnodeserver \
        --group=system:nodes
```

## 启动node节点各个组件
```bash
ansible -i ./k8s/hosts.ini kube-node -m shell -a "systemctl daemon-reload"
ansible -i ./k8s/hosts.ini kube-node -m shell -a "systemctl start kubelet"
ansible -i ./k8s/hosts.ini kube-node -m shell -a "systemctl start kube-proxy"
ansible -i ./k8s/hosts.ini kube-node -m shell -a "systemctl enable kubelet"
ansible -i ./k8s/hosts.ini kube-node -m shell -a "systemctl enable kube-proxy"
```

## 在master查看
```bash
[root@master-1 ~]# kubectl get node
NAME      STATUS    ROLES      AGE       VERSION
node-1    Ready     k8s-node   1m        v1.10.2
node-2    Ready     k8s-node   1m        v1.10.2
node-3    Ready     k8s-node   1m        v1.10.2
```

## kubectl config文件
部署完成后，kubectl默认连接的是本机apiserver 8080端口进行管理的
我们这里需要配置集群管理配置文件
把生成的admin.config文件copy并重命名到所有master主机 ~/.kube/config 权限为600
```bash
export KUBE_APISERVER="https://internal-k8s-apiserver-463791052.us-west-1.elb.amazonaws.com:6443"
# 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/pki/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=admin.config
# 设置客户端认证参数
kubectl config set-credentials admin \
  --client-certificate=/etc/kubernetes/pki/admin.pem \
  --client-key=/etc/kubernetes/pki/admin-key.pem \
  --embed-certs=true \
  --kubeconfig=admin.config
# 设置上下文参数
kubectl config set-context kubernetes \
  --cluster=kubernetes \
  --user=admin \
  --kubeconfig=admin.config
# 设置默认上下文
kubectl config use-context kubernetes --kubeconfig=admin.config
```

# 部署calico
## 下载yaml模板并部署
```bash
wget https://docs.projectcalico.org/v3.1/getting-started/kubernetes/installation/rbac.yaml
wget https://docs.projectcalico.org/v3.1/getting-started/kubernetes/installation/hosted/calico.yaml

ETCD_CERT=`cat /etc/kubernetes/pki/etcd/etcd.pem | base64 | tr -d '\n'`
ETCD_KEY=`cat /etc/kubernetes/pki/etcd/etcd-key.pem | base64 | tr -d '\n'`
ETCD_CA=`cat /etc/kubernetes/pki/etcd/ca.pem | base64 | tr -d '\n'`
ETCD_ENDPOINTS="https://172.31.25.244:2379,https://172.31.29.234:2379,https://172.31.21.119:2379"

sed -i "s@.*etcd_endpoints:.*@\ \ etcd_endpoints:\ \"${ETCD_ENDPOINTS}\"@gi" calico.yaml

sed -i "s@.*etcd-cert:.*@\ \ etcd-cert:\ ${ETCD_CERT}@gi" calico.yaml
sed -i "s@.*etcd-key:.*@\ \ etcd-key:\ ${ETCD_KEY}@gi" calico.yaml
sed -i "s@.*etcd-ca:.*@\ \ etcd-ca:\ ${ETCD_CA}@gi" calico.yaml

sed -i 's@.*etcd_ca:.*@\ \ etcd_ca:\ "/calico-secrets/etcd-ca"@gi' calico.yaml
sed -i 's@.*etcd_cert:.*@\ \ etcd_cert:\ "/calico-secrets/etcd-cert"@gi' calico.yaml
sed -i 's@.*etcd_key:.*@\ \ etcd_key:\ "/calico-secrets/etcd-key"@gi' calico.yaml

#修改IPV4 POOL 地址段
 - name: CALICO_IPV4POOL_CIDR
   value: "10.10.0.0/16"
```

## 更改node节点kubelet 配置，增加 `--network-plugin=cni`
```bash
#完整配置如下
[root@node-1 ~]# cat /etc/kubernetes/kubelet
###
# kubernetes kubelet (minion) config

# The address for the info server to serve on (set to 0.0.0.0 or "" for all interfaces)
KUBELET_ADDRESS="--node-ip=172.31.20.35"

# The port for the info server to serve on
# KUBELET_PORT="--port=10250"

# You may leave this blank to use the actual hostname
KUBELET_HOSTNAME="--hostname-override=node-1"

# location of the api-server
# KUBELET_API_SERVER=""

# Add your own!
KUBELET_ARGS="  --bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \
                --cert-dir=/etc/kubernetes/pki \
                --cgroup-driver=cgroupfs \
                --network-plugin=cni \
                --cluster-dns=10.254.0.2 \
                --cluster-domain=cluster.local. \
                --fail-swap-on=false \
                --hairpin-mode promiscuous-bridge \
                --feature-gates=RotateKubeletClientCertificate=true,RotateKubeletServerCertificate=true \
                --node-labels=node-role.kubernetes.io/k8s-node=true \
                --image-gc-high-threshold=75 \
                --image-gc-low-threshold=60 \
                --kube-reserved=cpu=500m,memory=512Mi,ephemeral-storage=1Gi \
                --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \
                --system-reserved=cpu=1000m,memory=1024Mi,ephemeral-storage=1Gi \
                --serialize-image-pulls=false \
                --sync-frequency=30s \
                --pod-infra-container-image=gcr.io/google_containers/pause-amd64:3.1 \
                --resolv-conf=/etc/resolv.conf \
                --rotate-certificates"
```

## node节点安装 cni plugins
```bash
# 部署完成后kubelet日志正常
ansible -i ./k8s/hosts.ini kube-node -m script -a "./k8s/scripts/cni-plugins.sh"
```

## 测试节点网络连通性
在master节点执行
```bash
cat <<EOF > nginx-dm.yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: nginx-dm
spec:
  replicas: 5
  template:
    metadata:
      labels:
        name: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-svc
spec:
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
  selector:
    name: nginx
EOF
```

```bash
kubectl apply -f nginx-dm.yaml
```

## 查看ip分配情况和服务
```bash
[root@master-1 src]# kubectl get nodes,pods,svc -o wide
NAME          STATUS    ROLES      AGE       VERSION   EXTERNAL-IP   OS-IMAGE                KERNEL-VERSION               CONTAINER-RUNTIME
node/node-1   Ready     k8s-node   5d        v1.10.2   <none>        CentOS Linux 7 (Core)   3.10.0-693.21.1.el7.x86_64   docker://18.3.1
node/node-2   Ready     k8s-node   5d        v1.10.2   <none>        CentOS Linux 7 (Core)   3.10.0-693.21.1.el7.x86_64   docker://18.3.1
node/node-3   Ready     k8s-node   5d        v1.10.2   <none>        CentOS Linux 7 (Core)   3.10.0-693.21.1.el7.x86_64   docker://18.3.1

NAME                            READY     STATUS    RESTARTS   AGE       IP             NODE
pod/nginx-dm-65c7fbb56c-4ngfl   1/1       Running   0          3d        10.10.139.66   node-3
pod/nginx-dm-65c7fbb56c-dzwrf   1/1       Running   0          3d        10.10.84.129   node-1
pod/nginx-dm-65c7fbb56c-l8hs6   1/1       Running   0          3d        10.10.139.65   node-3
pod/nginx-dm-65c7fbb56c-pdhjd   1/1       Running   0          3d        10.10.247.1    node-2
pod/nginx-dm-65c7fbb56c-sf5hb   1/1       Running   0          3d        10.10.84.130   node-1

NAME                 TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE       SELECTOR
service/kubernetes   ClusterIP   10.254.0.1       <none>        443/TCP   5d        <none>
service/nginx-svc    ClusterIP   10.254.154.173   <none>        80/TCP    3d        name=nginx
```

## 查看calico网络信息和路由信息
```bash
#查看路由信息
[root@node-1 ~]# ip route show
default via 172.31.16.1 dev ens3
blackhole 10.10.84.128/26 proto bird
10.10.84.129 dev cali87fd9a96a1d scope link
10.10.84.130 dev cali08e51259d95 scope link
10.10.139.64/26 via 172.31.21.106 dev tunl0 proto bird onlink
10.10.247.0/26 via 172.31.29.102 dev tunl0 proto bird onlink
172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1
172.31.16.0/20 dev ens3 proto kernel scope link src 172.31.20.35
```

## node节点进行测试
```bash
[root@node-1 ~]#  curl  10.254.154.173
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```

# 部署coredns(在任意master节点)
## 下载coredns yaml模板
参考https://github.com/coredns/deployment/tree/master/kubernetes
```bash
# 这两个文件必须在一个目录
wget https://raw.githubusercontent.com/coredns/deployment/master/kubernetes/coredns.yaml.sed
wget https://raw.githubusercontent.com/coredns/deployment/master/kubernetes/deploy.sh
```

## coredns模板替换
```bash
# 此脚本会根据当前集群参数通过coredns.yaml.sed模板生成适用于当前环境的模板并导入
#认真阅读deploy.sh脚本 -i 选项指定cluster-dns ip地址
[root@master-1 ~]# sh ./deploy.sh -i 10.254.0.2 | kubectl apply -f -
serviceaccount "coredns" created
clusterrole.rbac.authorization.k8s.io "system:coredns" created
clusterrolebinding.rbac.authorization.k8s.io "system:coredns" created
configmap "coredns" created
deployment.extensions "coredns" created
service "kube-dns" created
```

## 查看dns服务
```bash
[root@master-1 src]# kubectl get nodes,svc,pods -n kube-system -o wide
NAME          STATUS    ROLES      AGE       VERSION   EXTERNAL-IP   OS-IMAGE                KERNEL-VERSION               CONTAINER-RUNTIME
node/node-1   Ready     k8s-node   5d        v1.10.2   <none>        CentOS Linux 7 (Core)   3.10.0-693.21.1.el7.x86_64   docker://18.3.1
node/node-2   Ready     k8s-node   5d        v1.10.2   <none>        CentOS Linux 7 (Core)   3.10.0-693.21.1.el7.x86_64   docker://18.3.1
node/node-3   Ready     k8s-node   5d        v1.10.2   <none>        CentOS Linux 7 (Core)   3.10.0-693.21.1.el7.x86_64   docker://18.3.1

NAME               TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)         AGE       SELECTOR
service/kube-dns   ClusterIP   10.254.0.2   <none>        53/UDP,53/TCP   22s       k8s-app=kube-dns

NAME                                           READY     STATUS    RESTARTS   AGE       IP              NODE
pod/calico-kube-controllers-5b85d756c6-9hz4g   1/1       Running   0          3d        172.31.20.35    node-1
pod/calico-node-9w6km                          2/2       Running   0          3d        172.31.21.106   node-3
pod/calico-node-chdmg                          2/2       Running   0          3d        172.31.29.102   node-2
pod/calico-node-xwd8g                          2/2       Running   0          3d        172.31.20.35    node-1
pod/coredns-78f6d8759f-mprpz                   1/1       Running   0          22s       10.10.139.67    node-3
pod/coredns-78f6d8759f-s8br8                   1/1       Running   0          22s       10.10.247.2     node-2
```

## 部署dns自动扩容
- dns-horizontal-autoscaler.yaml
参考：https://github.com/kubernetes/kubernetes/blob/master/cluster/addons/dns-horizontal-autoscaler/dns-horizontal-autoscaler.yaml
```bash
cat <<EOF > dns-horizontal-autoscaler.yaml
# Copyright 2016 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

kind: ServiceAccount
apiVersion: v1
metadata:
  name: kube-dns-autoscaler
  namespace: kube-system
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: system:kube-dns-autoscaler
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
rules:
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["list"]
  - apiGroups: [""]
    resources: ["replicationcontrollers/scale"]
    verbs: ["get", "update"]
  - apiGroups: ["extensions"]
    resources: ["deployments/scale", "replicasets/scale"]
    verbs: ["get", "update"]
# Remove the configmaps rule once below issue is fixed:
# kubernetes-incubator/cluster-proportional-autoscaler#16
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "create"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: system:kube-dns-autoscaler
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
subjects:
  - kind: ServiceAccount
    name: kube-dns-autoscaler
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: system:kube-dns-autoscaler
  apiGroup: rbac.authorization.k8s.io

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kube-dns-autoscaler
  namespace: kube-system
  labels:
    k8s-app: kube-dns-autoscaler
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
spec:
  selector:
    matchLabels:
      k8s-app: kube-dns-autoscaler
  template:
    metadata:
      labels:
        k8s-app: kube-dns-autoscaler
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ''
    spec:
      priorityClassName: system-cluster-critical
      containers:
      - name: autoscaler
        image: k8s.gcr.io/cluster-proportional-autoscaler-amd64:1.1.2-r2
        resources:
            requests:
                cpu: "20m"
                memory: "10Mi"
        command:
          - /cluster-proportional-autoscaler
          - --namespace=kube-system
          - --configmap=kube-dns-autoscaler
          # Should keep target in sync with cluster/addons/dns/kube-dns.yaml.base
          - --target=Deployment/kube-dns
          # When cluster is using large nodes(with more cores), "coresPerReplica" should dominate.
          # If using small nodes, "nodesPerReplica" should dominate.
          - --default-params={"linear":{"coresPerReplica":256,"nodesPerReplica":16,"preventSinglePointFailure":true}}
          - --logtostderr=true
          - --v=2
      tolerations:
      - key: "CriticalAddonsOnly"
        operator: "Exists"
      serviceAccountName: kube-dns-autoscaler
EOF

kubectl apply -f dns-horizontal-autoscaler.yaml
```

# 生成ingress certs
```bash
#生成证书，最好使用公网签发证书，否则有些功能会出现错误
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=traefik-dev.dwnews.com"
kubectl -n kube-system create secret tls traefik-ui-secret --key=tls.key --cert=tls.crt
```

# 部署ingress负载均衡器
参考https://github.com/DevOps-Alvin/scripts/tree/master/k8s/traefik
注意修改traefik-ui.yaml的 域名和tls证书
```bash
kubectl apply -f https://raw.githubusercontent.com/DevOps-Alvin/scripts/master/k8s/examples/traefik/traefik-rbac.yaml

kubectl apply -f https://raw.githubusercontent.com/DevOps-Alvin/scripts/master/k8s/examples/traefik/traefik-configmap.yaml

kubectl apply -f https://raw.githubusercontent.com/DevOps-Alvin/scripts/master/k8s/examples/traefik/traefik-deployment.yaml

kubectl apply -f https://raw.githubusercontent.com/DevOps-Alvin/scripts/master/k8s/examples/traefik/traefik-ui.yaml
```

# 部署Heapster
官方已经废弃，但是替代方案metrics-server还未成熟，最重要的是整合度不好，观察阶段，后续稳定做迭代
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/influxdb.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/heapster.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/rbac/heapster-rbac.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/grafana.yaml
```

# 部署Dashboard
```bash
#非安全端口方式部署
kubectl apply -f  https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/alternative/kubernetes-dashboard.yaml


#安全端口方式部署（推荐）
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml

#用此方式部署，traefik-ingress模板里证书必须是公网可认证的否则无法访问，报404错误
kubectl apply -f https://raw.githubusercontent.com/DevOps-Alvin/scripts/master/k8s/examples/addons/dashboard/k8s-dashboard-ui.yaml
```

# 生成dashboard admin token
```bash
[root@master-1 dashboard]# sh dashboard_sa.sh
serviceaccount "dashboard-admin" created
clusterrolebinding.rbac.authorization.k8s.io "dashboard-admin" created
token:
.........略
```

# 部署EFK日志插件
```bash
#给node节点打标签
$ kubectl label nodes node-1 beta.kubernetes.io/fluentd-ds-ready=true
node "node-1" labeled
```

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/fluentd-elasticsearch/es-statefulset.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/fluentd-elasticsearch/es-service.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/fluentd-elasticsearch/fluentd-es-configmap.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/fluentd-elasticsearch/fluentd-es-ds.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/fluentd-elasticsearch/kibana-deployment.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/fluentd-elasticsearch/kibana-service.yaml
```