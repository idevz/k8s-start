#!/usr/bin/env bash

### BEGIN ###
# Author: idevz
# Since: 10:27:14 2019/08/16
# Description:       gen kubeconfigs for k8s componets
# gen-kubeconfig          ./gen-kubeconfig.sh
#
# Environment variables that control this script:
#
### END ###

set -e

BASE_DIR=${BASE_DIR:-$(dirname $(cd $(dirname "$0") && pwd -P)/$(basename "$0"))}
K8S_START_ROOT=${K8S_START_ROOT:-"${BASE_DIR}/.."}

[ -f "${K8S_START_ROOT}/kube-env" ] && source "${K8S_START_ROOT}/kube-env"
[ -f "${K8S_START_ROOT}/common/helpers.sh" ] && source "${K8S_START_ROOT}/common/helpers.sh"

BINS="${K8S_START_ROOT}/build-images/bins/v${K8S_VERSION}"
KUBECTL=${BINS}/kubectl
PKI_PATH="${K8S_START_ROOT}/etc/kubernetes/pki"
KUBE_CONFIGS_ROOT="${BASE_DIR}/etc/kubernetes/configs"

# 启用证书认证，token认证，以及http basic认证
function kubeconfig::kubelet_bootstrap() {
    # 生成token文件
    local bootstrap_token=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
    cat >"${PKI_PATH}/bootstrap-token.csv" <<EOF
${bootstrap_token},kubelet-bootstrap,10001,"system:bootstrappers"
EOF
    # 生成http basic认证文件
    cat >"${PKI_PATH}/basic-auth.csv" <<EOF
admin,admin,1
EOF

    # 设置集群参数，即 api-server 的访问方式，给集群起个名字就叫 kubernetes
    ${KUBECTL} config set-cluster kubernetes \
        --certificate-authority="${PKI_PATH}/ca.pem" \
        --embed-certs=true \
        --server=${K8S_API_SERVER} \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/kubelet-bootstrap.conf"
    # 设置客户端认证参数，这里采用token认证
    ${KUBECTL} config set-credentials kubelet-bootstrap \
        --token="${bootstrap_token}" \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/kubelet-bootstrap.conf"
    # 设置上下文参数，用于连接用户kubelet-bootstrap与集群kubernetes
    ${KUBECTL} config set-context default \
        --cluster=kubernetes \
        --user=kubelet-bootstrap \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/kubelet-bootstrap.conf"
    ${KUBECTL} config use-context default --kubeconfig="${KUBE_CONFIGS_ROOT}/kubelet-bootstrap.conf"
}

function kubeconfig::kube_controller_manager() {
    ${KUBECTL} config set-cluster kubernetes \
        --certificate-authority="${PKI_PATH}/ca.pem" \
        --embed-certs=true \
        --server=${K8S_API_SERVER} \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/kube-controller-manager.conf"
    ${KUBECTL} config set-credentials kube-controller-manager \
        --client-certificate="${PKI_PATH}/kube-controller-manager.pem" \
        --client-key="${PKI_PATH}/kube-controller-manager-key.pem" \
        --embed-certs=true \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/kube-controller-manager.conf"
    ${KUBECTL} config set-context default \
        --cluster=kubernetes \
        --user=kube-controller-manager \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/kube-controller-manager.conf"
    ${KUBECTL} config use-context default --kubeconfig="${KUBE_CONFIGS_ROOT}/kube-controller-manager.conf"
}

function kubeconfig::kube_scheduler() {
    ${KUBECTL} config set-cluster kubernetes \
        --certificate-authority="${PKI_PATH}/ca.pem" \
        --embed-certs=true \
        --server=${K8S_API_SERVER} \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/kube-scheduler.conf"
    ${KUBECTL} config set-credentials kube-scheduler \
        --client-certificate="${PKI_PATH}/kube-scheduler.pem" \
        --client-key="${PKI_PATH}/kube-scheduler-key.pem" \
        --embed-certs=true \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/kube-scheduler.conf"
    ${KUBECTL} config set-context default \
        --cluster=kubernetes \
        --user=kube-scheduler \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/kube-scheduler.conf"
    ${KUBECTL} config use-context default --kubeconfig="${KUBE_CONFIGS_ROOT}/kube-scheduler.conf"
}

function kubeconfig::kube_proxy() {
    ${KUBECTL} config set-cluster kubernetes \
        --certificate-authority="${PKI_PATH}/ca.pem" \
        --embed-certs=true \
        --server=${K8S_API_SERVER} \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/kube-proxy.conf"
    ${KUBECTL} config set-credentials kube-proxy \
        --client-certificate="${PKI_PATH}/kube-proxy.pem" \
        --client-key="${PKI_PATH}/kube-proxy-key.pem" \
        --embed-certs=true \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/kube-proxy.conf"
    ${KUBECTL} config set-context default \
        --cluster=kubernetes \
        --user=kube-proxy \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/kube-proxy.conf"
    ${KUBECTL} config use-context default --kubeconfig="${KUBE_CONFIGS_ROOT}/kube-proxy.conf"
}

function kubeconfig::admin() {
    ${KUBECTL} config set-cluster kubernetes \
        --certificate-authority="${PKI_PATH}/ca.pem" \
        --embed-certs=true \
        --server=${K8S_API_SERVER} \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/admin.conf"
    ${KUBECTL} config set-credentials admin \
        --client-certificate="${PKI_PATH}/admin.pem" \
        --client-key="${PKI_PATH}/admin-key.pem" \
        --embed-certs=true \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/admin.conf"
    ${KUBECTL} config set-context default \
        --cluster=kubernetes \
        --user=admin \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/admin.conf"
    ${KUBECTL} config use-context default --kubeconfig="${KUBE_CONFIGS_ROOT}/admin.conf"
}

function kubeconfig::kubelete() {
    local this_ip=$(h::get_this_ip)
    ${KUBECTL} config set-cluster kubernetes \
        --certificate-authority="${PKI_PATH}/ca.pem" \
        --embed-certs=true \
        --server=${K8S_API_SERVER} \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/kubelet-${this_ip}.conf"
    ${KUBECTL} config set-credentials "system:node:${this_ip}" \
        --client-certificate="${PKI_PATH}/kubelet.pem" \
        --client-key="${PKI_PATH}/kubelet-key.pem" \
        --embed-certs=true \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/kubelet-${this_ip}.conf"
    ${KUBECTL} config set-context default \
        --cluster=kubernetes \
        --user="system:node:${this_ip}" \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/kubelet-${this_ip}.conf"
    ${KUBECTL} config use-context default --kubeconfig="${KUBE_CONFIGS_ROOT}/kubelet-${this_ip}.conf"
}

function kubeconfig::mac() {
    [ ! $(uname) = "Darwin" ] && exit 1
    kubectl config set-cluster idevz-k8s \
        --certificate-authority="${PKI_PATH}/ca.pem" \
        --embed-certs=true \
        --server=${K8S_API_SERVER} \
        --kubeconfig="$HOME/.kube/config"
    kubectl config set-credentials idevz-k8s \
        --client-certificate="${PKI_PATH}/admin.pem" \
        --client-key="${PKI_PATH}/admin-key.pem" \
        --embed-certs=true \
        --kubeconfig="$HOME/.kube/config"
    kubectl config set-context idevz-k8s \
        --cluster=idevz-k8s \
        --user=idevz-k8s \
        --kubeconfig="$HOME/.kube/config"
    kubectl config use-context idevz-k8s --kubeconfig="$HOME/.kube/config"
}

function kubeconfig::local() {
    rm -rf "$HOME/.kube"
    mkdir -p "$HOME/.kube"
    sudo cp -i "${KUBE_CONFIGS_ROOT}/admin.conf" "$HOME/.kube/config"
    sudo chown $(id -u):$(id -g) "$HOME/.kube/config"
}

function kubeconfig::all() {
    kubeconfig::kubelet_bootstrap
    kubeconfig::kube_controller_manager
    kubeconfig::kube_scheduler
    kubeconfig::kube_proxy
    kubeconfig::kubelete
    kubeconfig::admin
}
