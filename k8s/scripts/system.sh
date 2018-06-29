#!/bin/bash

#配置epel源
yum install -y epel-release >/dev/null 2>&1

#安装 Development Tools 包
yum groupinstall -y "Development Tools" >/dev/null 2>&1

#安装net-tools
yum install -y net-tools

# kube-proxy ipvs模式所需以来包
yum install -y ipset conntrack-tools ipvsadm >/dev/null 2>&1

#配置SELINUX=disabled
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
#临时禁用，不需要重启
setenforce 0

# 配置内核参数
cat <<EOF > /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl -p /etc/sysctl.d/k8s.conf

# calico网络组件需要调整此参数
#参考https://docs.projectcalico.org/v3.1/usage/configuration/conntrack
sysctl -w net.netfilter.nf_conntrack_max=1000000
echo "net.netfilter.nf_conntrack_max=1000000" >> /etc/sysctl.conf

# 加载ipvs模块，kube-proxy 启用了ipvs模式 如果不满足这些要求，Kube-proxy将回退到IPTABLES模式。
# 参考https://github.com/kubernetes/kubernetes/tree/master/pkg/proxy/ipvs#when-ipvs-falls-back-to-iptables
cat <<EOF > /etc/sysconfig/modules/ipvs.modules
#!/bin/bash
ipvs_modules="ip_vs ip_vs_lc ip_vs_wlc ip_vs_rr ip_vs_wrr ip_vs_lblc ip_vs_lblcr ip_vs_dh ip_vs_sh ip_vs_fo ip_vs_nq ip_vs_sed ip_vs_ftp nf_conntrack_ipv4"
for kernel_module in \${ipvs_modules}; do
    /sbin/modinfo -F filename \${kernel_module} > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        /sbin/modprobe \${kernel_module}
    fi
done
EOF
chmod 750 /etc/sysconfig/modules/ipvs.modules && bash /etc/sysconfig/modules/ipvs.modules && lsmod | grep ip_vs


# 集群配置文件与证书目录
mkdir -p /etc/kubernetes/pki/etcd