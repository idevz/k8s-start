#!/usr/bin/env bash

### BEGIN ###
# Author: idevz
# Since: 10:15:01 2019/08/16
# Description:       prepare pki key and certs
# prepare-pki          ./prepare-pki.sh
#
# Environment variables that control this script:
#
### END ###

set -e
BASE_DIR=${BASE_DIR:-$(dirname $(cd $(dirname "$0") && pwd -P)/$(basename "$0"))}
K8S_START_ROOT=${K8S_START_ROOT:-"${BASE_DIR}/.."}

CFSSL="${K8S_START_ROOT}/common/tools/cfssl"
CFSSL_JSON="${K8S_START_ROOT}/common/tools/cfssljson"
CFSSL_CERTINFO="${K8S_START_ROOT}/common/tools/cfssl-certinfo"

PKI_PATH="${K8S_START_ROOT}/etc/kubernetes/pki"
PKI_JSON_PATH="${K8S_START_ROOT}/common/pki-jsons"

[ -f "${K8S_START_ROOT}/kube-env" ] && source "${K8S_START_ROOT}/kube-env"
[ -f "${K8S_START_ROOT}/common/helpers.sh" ] && source "${K8S_START_ROOT}/common/helpers.sh"

function pki::gen_jsons() {
    # ca-config.json：可以定义多个 profiles，分别指定不同的过期时间、使用场景等参数；后续在签名证书时使用某个 profile；
    # signing：表示该证书可用于签名其它证书；生成的 ca.pem 证书中 CA=TRUE；
    # server auth：表示client可以用该 CA 对server提供的证书进行验证；
    # client auth：表示server可以用该CA对client提供的证书进行验证；
    # "${CFSSL}" print-defaults config >"${PKI_JSON_PATH}/ca-config.json"

    # “CN”：Common Name，kube-apiserver 从证书中提取该字段作为请求的用户名 (User Name)；浏览器使用该字段验证网站是否合法；
    # “O”：Organization，kube-apiserver 从证书中提取该字段作为请求用户所属的组 (Group)；
    # "${CFSSL}" print-defaults csr >"${PKI_JSON_PATH}/ca-csr.json"

    # 如果 hosts 字段不为空则需要指定授权使用该证书的 IP 或域名列表，
    # 由于该证书后续被 etcd 集群和 kubernetes master 集群使用，
    # 所以上面分别指定了 etcd 集群、kubernetes master 集群的主机 IP
    # 和 kubernetes 服务的服务 IP（一般是 kue-apiserver
    # 指定的 service-cluster-ip-range 网段的第一个IP，如 10.254.0.1。
    # "${CFSSL}" print-defaults csr >"${PKI_JSON_PATH}/kubernetes-csr.json"

    # 后续 kube-apiserver 使用 RBAC 对客户端(如 kubelet、kube-proxy、Pod)请求进行授权；
    # kube-apiserver 预定义了一些 RBAC 使用的 RoleBindings，
    # 如 cluster-admin 将 Group system:masters 与 Role cluster-admin 绑定，
    # 该 Role 授予了调用kube-apiserver 的所有 API的权限；
    # OU 指定该证书的 Group 为 system:masters，kubelet 使用该证书访问 kube-apiserver 时 ，
    # 由于证书被 CA 签名，所以认证通过，同时由于证书用户组为经过预授权的 system:masters，所以被授予访问所有 API 的权限；
    # "${CFSSL}" print-defaults csr >"${PKI_JSON_PATH}/admin-csr.json"

    # CN 指定该证书的 User 为 system:kube-proxy；
    # kube-apiserver 预定义的 RoleBinding cluster-admin 将User system:kube-proxy 与 Role system:node-proxier 绑定，
    # 该 Role 授予了调用 kube-apiserver Proxy 相关 API 的权限；
    # "${CFSSL}" print-defaults csr >"${PKI_JSON_PATH}/kube-proxy-csr.json"
    echo "gen_jsons"
}

function pki::gen_ca() {
    local this_ip=$(h::get_this_ip)
    cd "${PKI_PATH}"
    "${CFSSL}" gencert -initca "${PKI_JSON_PATH}/ca-csr.json" | "${CFSSL_JSON}" -bare ca

    # 如果 hosts 字段不为空则需要指定授权使用该证书的 IP 或域名列表，
    # 由于该证书后续被 etcd 集群和 kubernetes master 集群使用，
    # 所以上面分别指定了 etcd 集群、kubernetes master 集群的主机 IP 和 kubernetes 服务的服务 IP
    # （一般是 kue-apiserver 指定的 service-cluster-ip-range 网段的第一个IP，如 10.254.0.1。
    sed "s#{{k8s_apiserver}}#${K8S_API_SERVER_ADVERTISE_ADDRESS}#g;
        s#{{k8s_cluster_gateway}}#${K8S_CLUSTER_GATEWAY}#g;
        s#{{k8s_cluster_domain}}#${K8S_CLUSTER_DOMAIN}#g" \
        "${PKI_JSON_PATH}/kubernetes-csr.json" |
        "${CFSSL}" gencert -ca="${PKI_PATH}/ca.pem" \
            -ca-key="${PKI_PATH}/ca-key.pem" \
            -config="${PKI_JSON_PATH}/ca-config.json" \
            -profile=kubernetes \
            - | "${CFSSL_JSON}" -bare kubernetes

    sed "s#{{k8s_apiserver}}#${K8S_API_SERVER_ADVERTISE_ADDRESS}#g;
        s#{{k8s_cluster_gateway}}#${K8S_CLUSTER_GATEWAY}#g;
        s#{{k8s_cluster_domain}}#${K8S_CLUSTER_DOMAIN}#g;
        s#{{k8s_node}}#system:node:${this_ip}#g" \
        "${PKI_JSON_PATH}"/kubelet-csr.json |
        "${CFSSL}" gencert -ca="${PKI_PATH}/ca.pem" \
            -ca-key="${PKI_PATH}/ca-key.pem" \
            -config="${PKI_JSON_PATH}/ca-config.json" \
            -profile=kubernetes \
            - | "${CFSSL_JSON}" -bare kubelet

    # kube-apiserver会提取CN作为客户端的用户名，这里是admin，将提取O作为用户的属组，这里是system:masters
    # 后续kube-apiserver使用RBAC对客户端（如kubelet、kube-proxy、pod）请求进行授权
    # apiserver预定义了一些RBAC使用的ClusterRoleBindings，
    # 例如 cluster-admin 将组 system:masters 与 CluasterRole cluster-admin 绑定，
    # 而 cluster-admin拥有访问apiserver的所有权限，因此admin用户将作为集群的超级管理员。
    "${CFSSL}" gencert -ca="${PKI_PATH}/ca.pem" \
        -ca-key="${PKI_PATH}/ca-key.pem" \
        -config="${PKI_JSON_PATH}/ca-config.json" \
        -profile=kubernetes \
        "${PKI_JSON_PATH}/admin-csr.json" | "${CFSSL_JSON}" -bare admin

    "${CFSSL}" gencert -ca="${PKI_PATH}/ca.pem" \
        -ca-key="${PKI_PATH}/ca-key.pem" \
        -config="${PKI_JSON_PATH}/ca-config.json" \
        -profile=kubernetes \
        "${PKI_JSON_PATH}/kube-controller-manager-csr.json" | "${CFSSL_JSON}" -bare kube-controller-manager

    "${CFSSL}" gencert -ca="${PKI_PATH}/ca.pem" \
        -ca-key="${PKI_PATH}/ca-key.pem" \
        -config="${PKI_JSON_PATH}/ca-config.json" \
        -profile=kubernetes \
        "${PKI_JSON_PATH}/kube-scheduler-csr.json" | "${CFSSL_JSON}" -bare kube-scheduler

    # CN指定该证书的user为system:kube-proxy
    # kube-apiserver预定义的RoleBinding 将User system:kube-proxy与Role system:node-proxier绑定，
    # 该role授予了调用kube-apiserver Proxy相关API的权限；
    "${CFSSL}" gencert --ca="${PKI_PATH}/ca.pem" \
        -ca-key="${PKI_PATH}/ca-key.pem" \
        -config="${PKI_JSON_PATH}/ca-config.json" \
        -profile=kubernetes \
        "${PKI_JSON_PATH}/kube-proxy-csr.json" | "${CFSSL_JSON}" -bare kube-proxy

    # 确认 Issuer 字段的内容和 ca-csr.json 一致；
    # 确认 Subject 字段的内容和 kubernetes-csr.json 一致；
    # 确认 X509v3 Subject Alternative Name 字段的内容和 kubernetes-csr.json 一致；
    # 确认 X509v3 Key Usage、Extended Key Usage 字段的内容和 ca-config.json 中 kubernetes profile 一致；
    openssl x509 -noout -text -in "${PKI_PATH}/kubernetes.pem"
    "${CFSSL_CERTINFO}" -cert "${PKI_PATH}/kubernetes.pem"

    # 将生成的证书和秘钥文件（后缀名为.pem）拷贝到所有机器的 /etc/kubernetes/ssl 目录下备用；
    # $ sudo mkdir -p /etc/kubernetes/ssl
    # $ sudo cp *.pem /etc/kubernetes/ssl
    cd -
}

function pki::service_account() {
    openssl genrsa -out "${PKI_PATH}/sa.key" 2048
    openssl rsa -in "${PKI_PATH}/sa.key" -pubout -out "${PKI_PATH}/sa.pub"
}

function pki::all() {
    pki::gen_ca
}
