#!/bin/bash

#卸载旧版本
yum remove -y docker \
                  docker-common \
                  docker-selinux \
                  docker-engine

#安装依赖包
yum install -y yum-utils \
  device-mapper-persistent-data \
  lvm2

#配置docker yum源
yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo

#安装docker-ce
yum install -y docker-ce-18.03.1.ce-1.el7.centos

#配置docker守护进程
cat <<EOF > /etc/systemd/system/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd --log-driver=json-file --log-opt=max-size=10m --log-opt=max-file=5
ExecStartPost=/usr/sbin/iptables -P FORWARD ACCEPT
ExecReload=/bin/kill -s HUP $MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TimeoutStartSec=0
Delegate=yes
KillMode=process
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start docker
systemctl enable docker