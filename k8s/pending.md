# 部署metrics-server 替代heapster
部署之后会报错需要在apiserver配置文件中增加配置
```bash
参考：
https://github.com/kubernetes/kubernetes/tree/master/cluster/addons/metrics-server
```

# 配置apiserver
参考：启用 Metrics Server
https://kubernetes.io/docs/tasks/access-kubernetes-api/configure-aggregation-layer/

https://www.yangcs.net/posts/api-aggregation/

```bash
--requestheader-client-ca-file=/etc/kubernetes/pki/aggregator-ca.pem \\
--proxy-client-cert-file=/etc/kubernetes/pki/aggregator.pem \\
--proxy-client-key-file=/etc/kubernetes/pki/aggregator-key.pem \\
--requestheader-allowed-names=aggregator \\
--requestheader-extra-headers-prefix=X-Remote-Extra- \\
--requestheader-group-headers=X-Remote-Group \\
--requestheader-username-headers=X-Remote-User \\
#如果 kube-proxy 没有在 Master 上面运行，kube-proxy 还需要添加配置：
--enable-aggregator-routing=true \\
```