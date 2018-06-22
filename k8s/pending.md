# 部署metrics-server 替代heapster
部署之后会报错需要在apiserver配置文件中增加配置
```bash
git clone https://github.com/kubernetes-incubator/metrics-server.git
cd metrics-server
kubectl create -f deploy/1.8+/
```

# 配置apiserver
参考：启用 Metrics Server
https://kubernetes.io/docs/tasks/access-kubernetes-api/configure-aggregation-layer/

```bash
--requestheader-client-ca-file=/etc/kubernetes/pki/ca.pem \\
--proxy-client-cert-file=/etc/kubernetes/pki/kube-proxy.pem \\
--proxy-client-key-file=/etc/kubernetes/pki/kube-proxy-key.pem \\
--requestheader-allowed-names=aggregator \\
--requestheader-extra-headers-prefix=X-Remote-Extra- \\
--requestheader-group-headers=X-Remote-Group \\
--requestheader-username-headers=X-Remote-User \\
--enable-aggregator-routing=true \\
```