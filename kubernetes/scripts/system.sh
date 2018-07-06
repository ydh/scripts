#!/usr/bin/env bash

set -e

function disabled_selinux() {
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0
}

function software_package() {
    #epel-release: epel源
    #Development: Tools 开发包
    #net-tools: 网络工具包ifconfig、route、arp和netstat等命令行工具
    #ipset conntrack-tools ipvsadm: ipvs所需软件包
    yum install -y epel-release net-tools ipset conntrack-tools ipvsadm >/dev/null 2>&1
    yum groupinstall -y "Development Tools" >/dev/null 2>&1
}

function close_swap() {
    swapoff -a && sysctl -w vm.swappiness=0
    sed -i 's/.*swap.*/#&/' /etc/fstab
}

function k8s_kernel_parameter() {
# 配置内核参数
cat <<EOF > /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl -p /etc/sysctl.d/k8s.conf
}

function calico_kernel_parameter() {
    # calico网络组件需要调整此参数
    #参考https://docs.projectcalico.org/v3.1/usage/configuration/conntrack
    sysctl -w net.netfilter.nf_conntrack_max=1000000
    echo "net.netfilter.nf_conntrack_max=1000000" >> /etc/sysctl.conf
}

function ipvs_kernel_module() {
# 加载ipvs模块，kube-proxy 启用了ipvs模式 如果不满足这些要求，Kube-proxy将回退到IPTABLES模式。
# 参考https://github.com/kubernetes/kubernetes/tree/master/pkg/proxy/ipvs#when-ipvs-falls-back-to-iptables
cat <<EOF > /etc/sysconfig/modules/ipvs.modules
#!/usr/bin/env bash
ipvs_modules="ip_vs ip_vs_lc ip_vs_wlc ip_vs_rr ip_vs_wrr ip_vs_lblc ip_vs_lblcr ip_vs_dh ip_vs_sh ip_vs_fo ip_vs_nq ip_vs_sed ip_vs_ftp nf_conntrack_ipv4"
for kernel_module in \${ipvs_modules}; do
    /sbin/modinfo -F filename \${kernel_module} > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        /sbin/modprobe \${kernel_module}
    fi
done
EOF
chmod 750 /etc/sysconfig/modules/ipvs.modules && bash /etc/sysconfig/modules/ipvs.modules && lsmod | grep ip_vs
}

function create_dir() {
    # 集群配置文件与证书目录
    mkdir -p /etc/kubernetes/pki/etcd
    # node节点nginx-proxy配置文件目录
    mkdir -p /etc/nginx
}


function install_docker() {
    yum remove -y docker \
                    docker-common \
                    docker-selinux \
                    docker-engine

    yum install -y yum-utils \
      device-mapper-persistent-data \
      lvm2

    yum-config-manager \
        --add-repo \
        https://download.docker.com/linux/centos/docker-ce.repo

    yum install -y docker-ce-18.03.1.ce-1.el7.centos
}


disabled_selinux
software_package
close_swap
k8s_kernel_parameter
calico_kernel_parameter
ipvs_kernel_module
create_dir

install_docker
systemctl daemon-reload
systemctl start docker
systemctl enable docker
