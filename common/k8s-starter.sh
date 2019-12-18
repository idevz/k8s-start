#!/usr/bin/env bash

### BEGIN ###
# Author: idevz
# Since: 10:38:48 2019/08/16
# Description:       start k8s componets
# k8s-starter          ./k8s-starter.sh
#
# Environment variables that control this script:
#
### END ###

set -e

BASE_DIR=${BASE_DIR:-$(dirname $(cd $(dirname "$0") && pwd -P)/$(basename "$0"))}
K8S_START_ROOT=${K8S_START_ROOT:-"${BASE_DIR}/.."}

[ -f "${K8S_START_ROOT}/kube-env" ] && source "${K8S_START_ROOT}/kube-env"
[ -f "${K8S_START_ROOT}/common/helpers.sh" ] && source "${K8S_START_ROOT}/common/helpers.sh"

PKI_PATH="${K8S_START_ROOT}/etc/kubernetes/pki"
KUBE_CONFIGS_ROOT="${K8S_START_ROOT}/etc/kubernetes/configs"

K8S_RUN_PATH="${K8S_START_ROOT}/k8s-run-path"
BINS="${K8S_START_ROOT}/build-images/bins/v${K8S_VERSION}"
KUBELET="${BINS}/kubelet"
MAINFEST_PATH="${K8S_START_ROOT}/etc/kubernetes/manifests"

DOCKER_IMAGE_PREFIX="zhoujing"
PAUSE_IMAGE="zhoujing/k8s-pause:3.1"
SLEEP_SECOND=1
KUBE_LOG_LEVEL=8
THIS_IP=$(h::get_this_ip)

function kstart::etcd() {
    local image="${DOCKER_IMAGE_PREFIX}/etcd:3.3.10"
    local container_name="k8s-etcd"
    docker stop ${container_name} &&
        sleep ${SLEEP_SECOND}
    docker run --rm --name ${container_name} \
        --net=host \
        -v "${PKI_PATH}":/etc/kubernetes/pki \
        -v "${K8S_RUN_PATH}/etcd_data":/var/etcd/data \
        -d ${image} \
        /etcd --name "${container_name}" \
        --data-dir=/data/etcd \
        --cert-file=/etc/kubernetes/pki/kubernetes.pem \
        --key-file=/etc/kubernetes/pki/kubernetes-key.pem \
        --peer-cert-file=/etc/kubernetes/pki/kubernetes.pem \
        --peer-key-file=/etc/kubernetes/pki/kubernetes-key.pem \
        --trusted-ca-file=/etc/kubernetes/pki/ca.pem \
        --peer-trusted-ca-file=/etc/kubernetes/pki/ca.pem \
        --initial-advertise-peer-urls=https://${ETCD_MASTER_IP}:2380 \
        --listen-peer-urls=https://${ETCD_MASTER_IP}:2380 \
        --listen-client-urls=https://${ETCD_MASTER_IP}:2379,https://127.0.0.1:2379 \
        --advertise-client-urls=https://${ETCD_MASTER_IP}:2379
}

function k8s::check_etcd_heath() {
    "${BINS}/etcdctl" --endpoints "https://${ETCD_MASTER_IP}:2379" \
        --ca-file="${PKI_PATH}/ca.pem" \
        --cert-file="${PKI_PATH}/kubernetes.pem" \
        --key-file="${PKI_PATH}/kubernetes-key.pem" \
        cluster-health
}

function kstart::kube_apiserver() {
    local image="${DOCKER_IMAGE_PREFIX}/kube-apiserver:${K8S_VERSION}"
    local container_name="k8s-kube-apiserver"
    docker stop ${container_name} ||
        sleep ${SLEEP_SECOND}
    docker run --rm --name ${container_name} \
        --net=host \
        -v "${PKI_PATH}":/etc/kubernetes/pki \
        -d ${image} \
        /kube-apiserver \
        --logtostderr=true \
        --v=${KUBE_LOG_LEVEL} \
        --advertise-address="${K8S_API_SERVER_ADVERTISE_ADDRESS}" \
        --etcd-servers=https://${ETCD_MASTER_IP}:2379 \
        --etcd-cafile=/etc/kubernetes/pki/ca.pem \
        --etcd-certfile=/etc/kubernetes/pki/kubernetes.pem \
        --etcd-keyfile=/etc/kubernetes/pki/kubernetes-key.pem \
        --service-cluster-ip-range="${K8S_CLUSTER_IP_CIDR}" \
        --enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota \
        --apiserver-count=3 \
        --secure-port=6443 \
        --runtime-config=rbac.authorization.k8s.io/v1 \
        --kubelet-https=true \
        --service-account-key-file=/etc/kubernetes/pki/ca-key.pem \
        --event-ttl=1h \
        --allow-privileged=true \
        --authorization-mode=Node,RBAC \
        --enable-bootstrap-token-auth=true \
        --basic-auth-file=/etc/kubernetes/pki/basic-auth.csv \
        --token-auth-file=/etc/kubernetes/pki/bootstrap-token.csv \
        --service-node-port-range=30000-32767 \
        --tls-cert-file=/etc/kubernetes/pki/kubernetes.pem \
        --tls-private-key-file=/etc/kubernetes/pki/kubernetes-key.pem \
        --client-ca-file=/etc/kubernetes/pki/ca.pem \
        --enable-swagger-ui=true \
        --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname \
        --anonymous-auth=false \
        --requestheader-allowed-names=kubernetes \
        --requestheader-client-ca-file=/etc/kubernetes/pki/kubernetes.pem \
        --requestheader-extra-headers-prefix=X-Remote-Extra- \
        --requestheader-group-headers=X-Remote-Group \
        --requestheader-username-headers=X-Remote-User \
        --kubelet-client-certificate=/etc/kubernetes/pki/admin.pem \
        --kubelet-client-key=/etc/kubernetes/pki/admin-key.pem #KUBE_APISERVER_ARGS
    #         --requestheader-client-ca-file=<path to aggregator CA cert>
    # --requestheader-allowed-names=front-proxy-client
    # --requestheader-extra-headers-prefix=X-Remote-Extra-
    # --requestheader-group-headers=X-Remote-Group
    # --requestheader-username-headers=X-Remote-User
    # --proxy-client-cert-file=<path to aggregator proxy cert>
    # --proxy-client-key-file=<path to aggregator proxy key>
}

function kstart::kube_controller_manager() {
    local image="${DOCKER_IMAGE_PREFIX}/kube-controller-manager:${K8S_VERSION}"
    local container_name="k8s-kube-controller-manager"
    docker stop ${container_name} ||
        sleep ${SLEEP_SECOND}
    docker run --rm --name ${container_name} \
        --net=host \
        -v "${PKI_PATH}":/etc/kubernetes/pki \
        -v "${KUBE_CONFIGS_ROOT}":/etc/kubernetes/kube-confs \
        -d ${image} \
        /kube-controller-manager \
        --logtostderr=true \
        --v=${KUBE_LOG_LEVEL} \
        --bind-address=127.0.0.1 \
        --kubeconfig=/etc/kubernetes/kube-confs/kube-controller-manager.conf \
        --cluster-cidr="${K8S_CLUSTER_IP_CIDR}" \
        --cluster-name=kubernetes \
        --cluster-signing-cert-file=/etc/kubernetes/pki/ca.pem \
        --cluster-signing-key-file=/etc/kubernetes/pki/ca-key.pem \
        --service-account-private-key-file=/etc/kubernetes/pki/ca-key.pem \
        --controllers=*,bootstrapsigner,tokencleaner \
        --root-ca-file=/etc/kubernetes/pki/ca.pem \
        --leader-elect=true \
        --use-service-account-credentials=true \
        --node-monitor-grace-period=10s \
        --pod-eviction-timeout=10s \
        --allocate-node-cidrs=true \
        --feature-gates=RotateKubeletServerCertificate=true,TTLAfterFinished=true
}

function kstart::kube_scheduler() {
    local image="${DOCKER_IMAGE_PREFIX}/kube-scheduler:${K8S_VERSION}"
    local container_name="k8s-kube-scheduler"
    docker stop ${container_name} ||
        sleep ${SLEEP_SECOND}
    docker run --rm --name ${container_name} \
        --net=host \
        -v "${PKI_PATH}":/etc/kubernetes/pki \
        -v "${KUBE_CONFIGS_ROOT}":/etc/kubernetes/kube-confs \
        -d ${image} \
        /kube-scheduler \
        --logtostderr=true \
        --v=${KUBE_LOG_LEVEL} \
        --port=0 \
        --kubeconfig=/etc/kubernetes/kube-confs/kube-scheduler.conf \
        --leader-elect=true \
        --address=127.0.0.1
}

function kstart::gen_kubelet_config() {
    local pki_path=${PKI_PATH}
    local mainfest_path=${MAINFEST_PATH}
    [ ! -z "${1}" ] && pki_path="${1}"
    [ ! -z "${2}" ] && mainfest_path="${2}"

    cat >"${KUBE_CONFIGS_ROOT}/kubelet-config-${THIS_IP}.yml" <<EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
address: "${THIS_IP}"
port: 10250
cgroupDriver: $(docker info -f '{{.CgroupDriver}}')
cgroupRoot: /
clusterDNS:
- "${K8S_CLUSTER_DNS}"
featureGates:
  SupportPodPidsLimit: false
#   SupportNodePidsLimit: false
clusterDomain: "${K8S_CLUSTER_DOMAIN}"
failSwapOn: false
hairpinMode: promiscuous-bridge
serializeImagePulls: false
authentication:
  x509:
    clientCAFile: ${pki_path}/ca.pem
  webhook:
    enabled: true
  anonymous:
    enabled: true
authorization:
  mode: Webhook
rotateCertificates: true
staticPodPath: ${mainfest_path}
EOF
}

function kstart::kubelet() {
    if [ -f "${K8S_RUN_PATH}/kubelet-${THIS_IP}.pid" ]; then
        local kubelet_pid=$(cat "${K8S_RUN_PATH}/kubelet-${THIS_IP}.pid")
        [ -d "/proc/${kubelet_pid}" ] && sudo kill "${kubelet_pid}"
    fi
    kstart::gen_kubelet_config

    nohup sudo "${KUBELET}" \
        --logtostderr=true \
        --v=${KUBE_LOG_LEVEL} \
        --hostname-override="${THIS_IP}" \
        --pod-infra-container-image=${PAUSE_IMAGE} \
        --config="${KUBE_CONFIGS_ROOT}/kubelet-config-${THIS_IP}.yml" \
        --kubeconfig="${KUBE_CONFIGS_ROOT}/kubelet-${THIS_IP}.conf" \
        --cert-dir="${PKI_PATH}" \
        --network-plugin=cni >"${K8S_RUN_PATH}/kubelet.log" 2>&1 &

    # nohup sudo "${KUBELET}" \
    #     --pod-infra-container-image=${PAUSE_IMAGE} \
    #     --network-plugin=cni \
    #     --container-runtime=docker \
    #     --kubeconfig="${KUBE_CONFIGS_ROOT}/kubelet-${THIS_IP}.conf" \
    #     --config="${KUBE_CONFIGS_ROOT}/kubelet-config-${THIS_IP}.yml" \
    #     --cert-dir="${PKI_PATH}" \
    #     --hostname-override=${THIS_IP} \
    #     --v=${KUBE_LOG_LEVEL} >"${K8S_RUN_PATH}/kubelet.log" 2>&1 &
    # --bootstrap-kubeconfig="${KUBE_CONFIGS_ROOT}/kubelet-bootstrap.conf" \

    echo -n $! >"${K8S_RUN_PATH}/kubelet-${THIS_IP}.pid"
}

function kstart::kubelet_service_unit_init() {
    local kubelet_exec="/usr/local/bin/kubelet"
    local config="/etc/kubernetes/kubelet-config-${THIS_IP}.yml"
    local kubeconfig="/etc/kubernetes/kubelet-${THIS_IP}.conf"
    local pki_path="/etc/kubernetes/pki"
    local mainfest_path="/etc/kubernetes/manifests"

    kstart::gen_kubelet_config ${pki_path} ${mainfest_path}

    [ ! -d "${pki_path}" ] && sudo mkdir -p "${pki_path}"
    [ ! -d "${mainfest_path}" ] && sudo mkdir -p "${mainfest_path}"

    sudo cp ${KUBELET} ${kubelet_exec}
    sudo cp ${PKI_PATH}/* ${pki_path}
    sudo cp ${MAINFEST_PATH}/* ${mainfest_path}
    sudo cp "${KUBE_CONFIGS_ROOT}/kubelet-config-${THIS_IP}.yml" ${config}
    sudo cp "${KUBE_CONFIGS_ROOT}/kubelet-${THIS_IP}.conf" ${kubeconfig}

    local kubelet_service_unit=$(
        cat <<KUBELET_SERVICE
[Unit] 
Description=Kubernetes Kubelet Documentation=https://github.com/kubernetes/kubernetes 

[Service] 
#ExecStartPre=/usr/bin/mkdir -p /etc/kubernetes

ExecStart=${kubelet_exec} \
        --logtostderr=true \
        --v=2 \
        --hostname-override=${THIS_IP} \
        --pod-infra-container-image=${PAUSE_IMAGE} \
        --config=${config} \
        --kubeconfig=${kubeconfig} \
        --cert-dir=${pki} \
        --network-plugin=cni

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
# set delegate yes so that systemd does not reset the cgroups of kubelet containers
Delegate=yes
# kill only the kubelet process, not all processes in the cgroup
KillMode=process
# restart the kubelet process if it exits prematurely
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s

Restart=on-failure 
RestartSec=5 

[Install]
WantedBy=multi-user.target
KUBELET_SERVICE
    )
    h::sudo_write "${kubelet_service_unit}" "/usr/lib/systemd/system/kubelet.service"
    sudo systemctl daemon-reload
    sudo systemctl start kubelet
    sudo systemctl enable kubelet
}

function kstart::x_local_kubelet() {
    if [ -f "${K8S_RUN_PATH}/kubelet-${THIS_IP}.pid" ]; then
        local kubelet_pid=$(cat "${K8S_RUN_PATH}/kubelet-${THIS_IP}.pid")
        [ -d "/proc/${kubelet_pid}" ] && sudo kill "${kubelet_pid}"
    fi
}

function kstart::kube_proxy() {
    local image="${DOCKER_IMAGE_PREFIX}/kube-proxy"
    local container_name="k8s-kube-proxy"
    docker stop ${container_name} ||
        sleep ${SLEEP_SECOND}
    docker run --rm --name ${container_name} \
        --net=host \
        -v "${PKI_PATH}":/etc/kubernetes/pki \
        -v "${KUBE_CONFIGS_ROOT}":/etc/kubernetes/kube-confs \
        --privileged \
        ${image} \
        /kube-proxy \
        --logtostderr=true \
        --v=${KUBE_LOG_LEVEL} \
        --kubeconfig=/etc/kubernetes/kube-confs/kube-proxy.conf \
        --bind-address="${THIS_IP}" \
        --proxy-mode=iptables \
        --hostname-override="${THIS_IP}" \
        --cluster-cidr="${K8S_CLUSTER_IP_CIDR}"
}

function kstart::all() {
    kstart::etcd
    kstart::kube_apiserver
    kstart::kube_controller_manager
    kstart::kube_scheduler
    kstart::kubelet
}
