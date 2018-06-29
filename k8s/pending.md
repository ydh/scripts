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
--requestheader-client-ca-file=/etc/kubernetes/pki/ca.pem \\
--proxy-client-cert-file=/etc/kubernetes/pki/kube-proxy.pem \\
--proxy-client-key-file=/etc/kubernetes/pki/kube-proxy-key.pem \\
--requestheader-allowed-names=aggregator \\
--requestheader-extra-headers-prefix=X-Remote-Extra- \\
--requestheader-group-headers=X-Remote-Group \\
--requestheader-username-headers=X-Remote-User \\
--enable-aggregator-routing=true \\
```

# 部署EFK
所需镜像
docker.elastic.co/kibana/kibana-oss:6.3.0
docker.elastic.co/elasticsearch/elasticsearch-oss:6.3.0
Fluentd
https://github.com/fluent/fluentd-kubernetes-daemonset/blob/master/fluentd-daemonset-elasticsearch.yaml