#!/usr/bin/env bash

### BEGIN ###
# Author: idevz
# Since: 16:07:57 2019/08/16
# Description:       addons for k8s
# addons          ./addons.sh
#
# Environment variables that control this script:
#
### END ###

set -e

BASE_DIR=${BASE_DIR:-$(dirname $(cd $(dirname "$0") && pwd -P)/$(basename "$0"))}
K8S_START_ROOT=${K8S_START_ROOT:-"${BASE_DIR}/.."}

[ -f "${K8S_START_ROOT}/kube-env" ] && source "${K8S_START_ROOT}/kube-env"
BINS="${K8S_START_ROOT}/build-images/bins/${K8S_VERSION}"

KUBE_CONFIGS_ROOT="${K8S_START_ROOT}/etc/kubernetes/configs"
PKI_PATH="${K8S_START_ROOT}/etc/kubernetes/pki"

ADDONS="${K8S_START_ROOT}/addons"

function addons::all() {
    declare -A K8S_YAML_ARR
    K8S_YAML_ARR=(
        [kube_proxy]="kube-proxy.yaml"
        [calico]="calico.yaml"
        [coredns]="coredns.yaml"
        [dashboard]="kubernetes-dashboard.yaml"
    )
    for key in ${!K8S_YAML_ARR[*]}; do
        "addons::${key}" ${K8S_YAML_ARR[$key]}
    done
}

function addons::kube_proxy() {
    local k8s_yaml="kube-proxy.yaml"
    [ ! -z "${1}" ] && k8s_yaml="${1}"
    sed "s#{{k8s_cluster_ip_cidr}}#${K8S_CLUSTER_IP_CIDR}#g;
    s#{{k8s_configs_root}}#${KUBE_CONFIGS_ROOT}#g" \
        "${ADDONS}/tpl/${k8s_yaml}" >"${ADDONS}/${k8s_yaml}"
    "${BINS}/kubectl" apply -f "${ADDONS}/${k8s_yaml}"
}

function addons::calico() {
    # TODO calico etcd
    #   Normal   Scheduled         <unknown>             default-scheduler  Successfully assigned kube-system/calico-kube-controllers-f9c88cc7b-xspg5 to kube1
    #   Warning  FailedMount       15s (x2 over 2m32s)   kubelet, kube1     Unable to attach or mount volumes: unmounted volumes=[etcd-certs calico-kube-controllers-token-85hd5], unattached volumes=[etcd-certs calico-kube-controllers-token-85hd5]: timed out waiting for the condition
    #   Warning  FailedMount       14s (x10 over 4m33s)  kubelet, kube1     MountVolume.SetUp failed for volume "etcd-certs" : failed to sync secret cache: timed out waiting for the condition
    #   Warning  FailedMount       14s (x10 over 4m33s)  kubelet, kube1     MountVolume.SetUp failed for volume "calico-kube-controllers-token-85hd5" : failed to sync secret cache: timed out waiting for the condition
    local etcd_ca=$(base64 "${PKI_PATH}/ca.pem" | tr -d '\n')
    local etcd_key=$(base64 "${PKI_PATH}/kubernetes-key.pem" | tr -d '\n')
    local etcd_cert=$(base64 "${PKI_PATH}/kubernetes.pem" | tr -d '\n')
    local k8s_yaml="calico.yaml"
    [ ! -z "${1}" ] && k8s_yaml="${1}"
    sed "s#{{etcd_server}}#${ETCD_SERVER}#g;
    s#{{etcd_ca}}#${etcd_ca}#g;
    s#{{etcd_key}}#${etcd_key}#g;
    s#{{etcd_cert}}#${etcd_cert}#g;
    s#{{k8s_pod_ip_cidr}}#${K8S_POD_IP_CIDR}#g;
    s#{{calico_ip_detect_host}}#${MACHINE_IP_DETECT_HOST}#g" \
        "${ADDONS}/tpl/${k8s_yaml}" >"${ADDONS}/${k8s_yaml}"
    "${BINS}/kubectl" apply -f "${ADDONS}/${k8s_yaml}"
}

function addons::coredns() {
    local k8s_yaml="coredns.yaml"
    [ ! -z "${1}" ] && k8s_yaml="${1}"
    sed "s#{{k8s_cluster_domain}}#${K8S_CLUSTER_DOMAIN}#g;
    s#{{k8s_cluster_dns}}#${K8S_CLUSTER_DNS}#g" \
        "${ADDONS}/tpl/${k8s_yaml}" >"${ADDONS}/${k8s_yaml}"
    "${BINS}/kubectl" apply -f "${ADDONS}/${k8s_yaml}"
}

function addons::dashboard() {
    local k8s_yaml="kubernetes-dashboard.yaml"
    [ ! -z "${1}" ] && k8s_yaml="${1}"
    "${BINS}/kubectl" apply -f "${ADDONS}/${k8s_yaml}"
}

function addons::x() {
    [ -z "${1}" ] && return 1
    "${BINS}/kubectl" delete -f "${ADDONS}/${1}"
}

function addons::xall() {
    "${BINS}/kubectl" delete -f "${ADDONS}/"
}
