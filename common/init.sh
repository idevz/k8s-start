#!/usr/bin/env bash

### BEGIN ###
# Author: idevz
# Since: 16:25:54 2019/08/16
# Description:       init k8s env / pvms
# init          ./init.sh
#
# Environment variables that control this script:
#
### END ###

set -e

BASE_DIR=${BASE_DIR:-$(dirname $(cd $(dirname "$0") && pwd -P)/$(basename "$0"))}
K8S_START_ROOT=${K8S_START_ROOT:-"${BASE_DIR}/.."}
K8S_VERSION=${K8S_VERSION:-"1.14"}

[ -f "${K8S_START_ROOT}/common/helpers.sh" ] && source "${K8S_START_ROOT}/common/helpers.sh"

HTTP_PROXY_ADDR="http://10.211.55.2:8118"
NO_PROXY="localhost,127.0.0.1,::1"

THIS_IP=$(h::get_this_ip)

function init::sysctl() {
    # 禁用selinux 让容器可以访问主机文件系统，比如：Pod 网络设置就需要此特性
    # 这个设置必须保持直到 kubelet 支持 SELinux
    # 永久关闭 修改/etc/sysconfig/selinux文件设置
    # sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/sysconfig/selinux
    sudo setenforce 0
    sudo sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/sysconfig/selinux


    # 临时关闭swap
    # 永久关闭 注释/etc/fstab文件里swap相关的行
    # 当前的Qos（Quality of Service）策略都是假定主机不启用内存Swap。
    # 如果主机启用了Swap，那么Qos策略可能会失效。
    # 例如：两个Pod都刚好达到了内存Limits，由于内存 Swap 机制，它们还可以继续申请使用更多的内存。
    # 如果Swap空间不足，那么最终这两个Pod中的进程可能会被“杀掉”。
    # 目前Kubernetes和Docker尚不支持内存Swap空间的隔离机制。
    swapoff -a && sysctl -w vm.swappiness=0

    # 测试环境关闭防火墙，保证全部端口开放。
    # https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#check-required-ports
    sudo systemctl stop firewalld &&
        sudo systemctl disable firewalld

    # 开启 forward
    # Docker 从 1.13 版本开始调整了默认的防火墙规则
    # 禁用了 iptables filter 表中 FOWARD 链
    # 这样会引起 Kubernetes 集群中跨 Node 的 Pod 无法通信
    sudo iptables -P FORWARD ACCEPT

    # RHEL/CentOS 7 可能有 由于iptables被绕过，导致流量路由不正确的问题，需要设置如下内核参数
    sysctl_conf=$(
        cat <<SYSCTL
net.bridge.bridge-nf-call-ip6tables=1
net.bridge.bridge-nf-call-iptables=1
net.ipv4.ip_forward=1
net.ipv6.conf.default.forwarding=1
vm.swappiness=0
SYSCTL
    )
    h::sudo_write "${sysctl_conf}" "/etc/sysctl.d/k8s.conf"
    sudo modprobe br_netfilter
    sudo sysctl --system

    # cat /sys/class/dmi/id/product_uuid
    # 如果需要部署多个节点则需要:
    # 1. 检查机器名称、mac 地址及 product_uuid 的唯一性
    # 2. 多台机器内网互通
}

# kube-proxy 支持 iptables 和 ipvs，如果条件满足，默认使用 ipvs，否则使用 iptables
# 创建 /etc/sysconfig/modules/ipvs.modules 文件，保证在节点重启后能自动加载所需模块
function init::ip_vs() {
    sudo cat >/etc/sysconfig/modules/ipvs.modules <<EOF
#!/bin/bash
ipvs_modules="ip_vs ip_vs_rr ip_vs_wrr ip_vs_sh nf_conntrack_ipv4"
for kernel_module in \${ipvs_modules}; do
    sudo /sbin/modinfo -F filename \${kernel_module} > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        sudo /sbin/modprobe \${kernel_module}
    fi
done
EOF
    sudo chmod 755 /etc/sysconfig/modules/ipvs.modules && sudo bash /etc/sysconfig/modules/ipvs.modules && sudo lsmod | grep -e ip_vs -e nf_conntrack_ipv4
    # 安装 ipset 软件包。 安装管理工具 ipvsadm 便于查看 ipvs 的代理规则
    sudo yum install -y ipset ipvsadm
    # 如果以上前提条件如果不满足，则即使 kube-proxy 的配置开启了 ipvs 模式，也会退回到 iptables 模式
}

# 检查是否已经安装有老版本 docker，按需执行
function init::clean_old_docker() {
    sudo yum remove -y docker \
        docker-client \
        docker-client-latest \
        docker-common \
        docker-latest \
        docker-latest-logrotate \
        docker-logrotate \
        docker-engine
}

function init::install_docker() {
    sudo yum install -y yum-utils \
        device-mapper-persistent-data \
        lvm2
    sudo yum-config-manager \
        --add-repo \
        https://download.docker.com/linux/centos/docker-ce.repo
    sudo yum-config-manager --enable docker-ce-edge
    sudo yum-config-manager --enable docker-ce-test
    # sudo yum-config-manager --disable docker-ce-edge
    sudo yum install -y docker-ce docker-ce-cli containerd.io
    local docker_service_unit=
    docker_service_unit=$(
        cat <<DOCKER_SERVICE
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
ExecStart=/usr/bin/dockerd \
          --ipv6  --fixed-cidr-v6=2001:470:19:fea::/64
ExecReload=/bin/kill -s HUP $MAINPID
# Environment="HTTP_PROXY=${HTTP_PROXY_ADDR}" "HTTPS_PROXY=${HTTP_PROXY_ADDR}" "NO_PROXY=${NO_PROXY}"
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
# Uncomment TasksMax if your systemd version supports it.
# Only systemd 226 and above support this version.
#TasksMax=infinity
TimeoutStartSec=0
# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes
# kill only the docker process, not all processes in the cgroup
KillMode=process
# restart the docker process if it exits prematurely
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target
DOCKER_SERVICE
    )
    h::sudo_write "${docker_service_unit}" "/lib/systemd/system/docker.service"
    sudo mkdir "/etc/docker"
    local docker_daemon_json=
    docker_daemon_json=$(
        cat <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF
    )
    h::sudo_write "${docker_daemon_json}" "/etc/docker/daemon.json"
    sudo mkdir -p /etc/systemd/system/docker.service.d
    sudo systemctl daemon-reload
    sudo systemctl start docker
    sudo systemctl enable docker
}

function init::kube_env() {
    cat <<KUBE_ENV >"${K8S_START_ROOT}/kube-env"
# DO NOT EDIT!!! This file is generated by "./run.sh init kube_env"
# NOTE: apiserver port must be 6443 and varibale can not contain '#'
K8S_VERSION=${K8S_VERSION}
ETCD_MASTER_IP="${THIS_IP}"
K8S_API_SERVER_ADVERTISE_ADDRESS=${THIS_IP}  # apiserver ip
K8S_API_SERVER=https://${THIS_IP}:6443  # apiserver address 6443 cannot change now
K8S_CLUSTER_DNS=10.1.0.10 # cluster dns ip
K8S_CLUSTER_IP_CIDR=10.1.0.0/16  # cluster ip range
K8S_CLUSTER_GATEWAY=10.1.0.1 # cluster gateway
K8S_CLUSTER_DOMAIN=k8s.idevz.org  #cluster domain
K8S_POD_IP_CIDR=10.2.0.0/16 # pod ip range
ETCD_SERVER=https://${THIS_IP}:2379 # etcd server the port 2379 cannot change now and now it's noly support http
MACHINE_IP_DETECT_HOST=i.api.weibo.com
KUBE_ENV
}

function init::kube_manifests() {
    local manifests_tpl_root="${K8S_START_ROOT}/addons/tpl/manifests"
    local manifests_rs_file_root="${K8S_START_ROOT}/etc/kubernetes/manifests"
    declare -A K8S_MANIFESTS_IMAGES
    K8S_MANIFESTS_IMAGES=(
        ["addon-manager"]="zhoujing/kube-addon-manager:v9.0"
        ["kube-apiserver"]="zhoujing/kube-apiserver:1.14"
        ["kube-scheduler"]="zhoujing/kube-scheduler:1.14"
        ["etcd"]="zhoujing/etcd:3.3.10"
        ["kube-controller-manager"]="zhoujing/kube-controller-manager:1.14"
    )
    for key in ${!K8S_MANIFESTS_IMAGES[*]}; do
        sed "s#{{K8S_START_ROOT}}#${K8S_START_ROOT}#g;
        s#{{K8S_API_SERVER_ADVERTISE_ADDRESS}}#${K8S_API_SERVER_ADVERTISE_ADDRESS}#g;
        s#{{ETCD_MASTER_IP}}#${ETCD_MASTER_IP}#g;
        s#{{K8S_CLUSTER_IP_CIDR}}#${K8S_CLUSTER_IP_CIDR}#g;
        s#{{IMAGE}}#${K8S_MANIFESTS_IMAGES[$key]}#g" \
            "${manifests_tpl_root}/${key}.yaml" >"${manifests_rs_file_root}/${key}.yaml"
    done
}

function init::all() {
    init::sysctl
    # if [ $(uname -a | grep -o el8) != 'el8' ]; then
    #     init::clean_old_docker
    #     init::install_docker
    # fi
    init::kube_env
    init::kube_manifests
}
