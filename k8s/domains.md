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
负载ELB 做4层和7层负载会出现 traefik白名单失效。X-Forwarded-* 传不过来真是客户ip头。
master节点解析node节点需要些hosts文件。
