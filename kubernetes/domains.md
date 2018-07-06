运维对外管理web域名规划：

traefik
开发环境、测试环境、预发布环境
traefik-dev.dwnews.net
生产环境
traefik-pro.dwnews.net

kubernetes dashboard
开发环境、测试环境、预发布环境
dashboard-dev.dwnews.net
生产环境
dashboard-pro.dwnews.net

jenkins
通用ci中心
jenkins.dwnews.net

spinnaker
通用调度中心
spinnaker.dwnews.net


问题：

负载ELB 做4层和7层负载会出现 traefik白名单失效。X-Forwarded-* 无法传递客户ip头。
（proxyProtocol forwardedHeaders）

dashboard 安全模板部署完成后无法使用，因无公网证书，不确定最终原因； http模板无问题。

资源限制需要测试

master节点解析node节点需要些hosts文件。

flannel网络组件host-gw模式在aws调试不通。问题未找到

运维层和研发层协调调度问题

微服务架构需要了解

jenkins


微服务管理框架service mesh——Istio 可以作为ingress。但是局限性比较大
微服务管理框架service mesh——Linkerd


监控prometheus & zabbix 存储s3 （直接在k8s集群上运行，还是独立出来是否需要监控非容器主机）