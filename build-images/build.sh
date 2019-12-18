#!/usr/bin/env bash

### BEGIN ###
# Author: idevz
# Since: 08:18:26 2019/08/11
# Description:       building k8s images
# build          ./build.sh xx
#
# Environment variables that control this script:
#
### END ###

set -ex
BASE_DIR=$(dirname $(cd $(dirname "$0") && pwd -P)/$(basename "$0"))

WITH_DEBUG="contain-debug"

BASE_IMAGE="centos"
DOCKER_TAG_PREFIX="zhoujing"
DEFAULT_DEBUG_PORT=40000
K8S_VERSION=${KV:-"1.12"}
BIN_PATH="${BASE_DIR}/bins/v${K8S_VERSION}"
DOCKER_RUN_PATH="${BASE_DIR}/run_path/v${K8S_VERSION}"
DLV="${BASE_DIR}/bins/dlv"

k8s_component=("kube-apiserver" "kube-controller-manager" "kube-proxy" "kube-scheduler" "kubelet")

function k8s::error() {
    echo "${1}" && exit 0
}

function build::binary() {
    make WHAT=cmd/kubectl KUBE_BUILD_PLATFORMS=linux/amd64 &&
        make WHAT=cmd/kube-apiserver KUBE_BUILD_PLATFORMS=linux/amd64 &&
        make WHAT=cmd/kube-controller-manager KUBE_BUILD_PLATFORMS=linux/amd64 &&
        make WHAT=cmd/kube-proxy KUBE_BUILD_PLATFORMS=linux/amd64 &&
        make WHAT=cmd/kube-scheduler KUBE_BUILD_PLATFORMS=linux/amd64 &&
        make WHAT=cmd/kubelet KUBE_BUILD_PLATFORMS=linux/amd64

    make GOGCFLAGS="-N -l" GOGCFLAGS="-e" WHAT=cmd/kubectl KUBE_BUILD_PLATFORMS=linux/amd64 &&
        make GOGCFLAGS="-N -l" GOGCFLAGS="-e" WHAT=cmd/kube-apiserver KUBE_BUILD_PLATFORMS=linux/amd64 &&
        make GOGCFLAGS="-N -l" GOGCFLAGS="-e" WHAT=cmd/kube-controller-manager KUBE_BUILD_PLATFORMS=linux/amd64 &&
        make GOGCFLAGS="-N -l" GOGCFLAGS="-e" WHAT=cmd/kube-proxy KUBE_BUILD_PLATFORMS=linux/amd64 &&
        make GOGCFLAGS="-N -l" GOGCFLAGS="-e" WHAT=cmd/kube-scheduler KUBE_BUILD_PLATFORMS=linux/amd64 &&
        make GOGCFLAGS="-N -l" GOGCFLAGS="-e" WHAT=cmd/kubelet KUBE_BUILD_PLATFORMS=linux/amd64
}

function build::prepare() {
    local pkg=${1}
    [ -z "${pkg}" ] && k8s::error "none pkg name got."
    [ -d ${DOCKER_RUN_PATH} ] &&
        rm -rf ${DOCKER_RUN_PATH}
    mkdir -p ${DOCKER_RUN_PATH}
    cp "${BIN_PATH}/${pkg}" "${DOCKER_RUN_PATH}/${pkg}"

    cat >"${DOCKER_RUN_PATH}/Dockerfile" <<Dockerfile
FROM ${BASE_IMAGE}
COPY ${pkg} /${pkg}
Dockerfile

    cat "${DOCKER_RUN_PATH}/Dockerfile"

    local debug=${2}
    if [[ -n "${debug}" ]]; then
        cp "${DLV}" "${DOCKER_RUN_PATH}/dlv"
        tee -a "${DOCKER_RUN_PATH}/Dockerfile" <<DebugDockerfile
COPY dlv /usr/local/bin/dlv
ENTRYPOINT ["/usr/local/bin/dlv", "--listen=:40000", "--headless=true", "--api-version=2", "exec", "/${pkg}", "--"]
EXPOSE ${DEFAULT_DEBUG_PORT}
DebugDockerfile
        cat "${DOCKER_RUN_PATH}/Dockerfile"
    fi
}

function build::bpimages() {
    if [[ -x $(which docker 2>/dev/null) ]]; then
        build::prepare "$@"
        local pkg=${1}
        local docker_tag="${DOCKER_TAG_PREFIX}/${pkg}:${K8S_VERSION}"
        local debug=${2}
        [[ -n "${debug}" ]] && docker_tag="${docker_tag}-debug"
        docker build -t "${docker_tag}" "${DOCKER_RUN_PATH}"
        docker push "${docker_tag}"
    else
        k8s::error "none docker command find."
    fi
}

do_what=${1}
shift

case "${do_what}" in
bp)
    # for pkg in "kube-controller-manager" "kube-proxy" "kube-scheduler"; do
    for pkg in ${k8s_component[*]}; do
        build::bpimages "${pkg}"
        build::bpimages "${pkg}" "${WITH_DEBUG}"
    done
    ;;
esac
