#!/usr/bin/env bash

### BEGIN ###
# Author: idevz
# Since: 21:10:55 2019/08/14
# Description:       some helper functions
# helpers          source ./helpers.sh
#
# Environment variables that control this script:
#
### END ###

set -e

BASE_DIR=${BASE_DIR:-$(dirname $(cd $(dirname "$0") && pwd -P)/$(basename "$0"))}

function h::fn_exists() {
    $(type "${1}" 2>/dev/null | grep -q 'function')
    return $?
}

function h::env_p_exists() {
    [ -z "${1}" ] && return 1
    return 0
}

function h::get_this_ip() {
    ! h::env_p_exists ${MACHINE_IP_DETECT_HOST} && return 1
    [ $(uname) != "Linux" ] && return 1
    echo $(python -c "
import socket;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.connect(('${MACHINE_IP_DETECT_HOST}',0));print(s.getsockname()[0])
")
}

function h::sudo_write() {
    local content="${1}"
    local file_name="${2}"
    local if_add=
    [ ! -z ${3} ] && if_add="-a"
    echo "${content}" | sudo tee ${if_add} "${file_name}" >/dev/null 2>&1
}

function h::local_common() {
    local common_shs=(
        "addons"
        "gen-kubeconfig"
        "helpers"
        "init"
        "k8s-starter"
        "prepare-pki"
    )

    for f in ${common_shs[*]}; do
        local common="${BASE_DIR}/common/${f}".sh
        [ -x "${common}" ] &&
            source ${common} || echo "error to source file: ${common}"
    done
}
