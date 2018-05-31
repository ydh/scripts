#!/bin/bash

if [ -d "/etc/nginx" ]; then
    mkdir -p "/etc/nginx"
if

# nginx代理配置文件
cat <<EOF > /etc/nginx/nginx.conf
error_log stderr notice;

worker_processes auto;
events {
        multi_accept on;
        use epoll;
        worker_connections 1024;
}

stream {
    upstream kube_apiserver {
        least_conn;
        server 172.31.25.244:6443;
        server 172.31.29.234:6443;
        server 172.31.21.119:6443;
    }

    server {
        listen        0.0.0.0:6443;
        proxy_pass    kube_apiserver;
        proxy_timeout 10m;
        proxy_connect_timeout 1s;
    }
}
EOF

# 创建nginx systemd守护进程
cat <<EOF > /etc/systemd/system/nginx-proxy.service
[Unit]
Description=kubernetes apiserver docker wrapper
Wants=docker.socket
After=docker.service

[Service]
User=root
PermissionsStartOnly=true
ExecStart=/usr/bin/docker run -p 127.0.0.1:6443:6443 \
                              -v /etc/nginx:/etc/nginx \
                              --name nginx-proxy \
                              --net=host \
                              --restart=on-failure:5 \
                              --memory=512M \
                              nginx:1.13.12-alpine
ExecStartPre=-/usr/bin/docker rm -f nginx-proxy
ExecStop=/usr/bin/docker stop nginx-proxy
Restart=always
RestartSec=15s
TimeoutStartSec=30s

[Install]
WantedBy=multi-user.target
EOF