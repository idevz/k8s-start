#!/usr/bin/env bash

### BEGIN ###
# Author: idevz
# Since: 09:33:25 2019/08/12
# Description:       k8s launch script
# run          ./run.sh
#
# 1. ./run.sh iksp  (init all dependent configs)
# 2. ./run.sh kstart kubelet_service_unit_init  (chosing to run under static pod mod)
# 3. ./run.sh kubeconfig local   (init a local kubeconf for manage the cluster)
# 4. ./run.sh addons all  (install addons,
#    now I didn't using the aonns path, because of the addon tpls)
#
# Environment variables that control this script:
#
### END ###

set -ex
BASE_DIR=$(dirname $(cd $(dirname "$0") && pwd -P)/$(basename "$0"))
K8S_START_ROOT=${BASE_DIR}

source ${K8S_START_ROOT}/common/helpers.sh && h::local_common || exit 1

do_what=${1}

case ${do_what} in
iksp | init_k8s_static_pod)
    init::all
    pki::gen_ca
    kubeconfig::all
    ;;
ikod | init_k8s_on_docker)
    init::sysctl
    init::clean_old_docker
    init::install_docker
    init::kube_env
    pki::gen_ca
    kubeconfig::all
    ;;
pki | kubeconfig | init | kstart | addons | h)
    fn="${do_what}::${2}"
    shift 2

    ! h::fn_exists "${fn}" && exit 1
    ${fn} "$@" && echo "done." && exit 0
    ;;
x | stop)
    sudo systemctl stop kubelet && sudo systemctl stop docker
    ;;
s | start)
    sudo systemctl start docker && sudo systemctl start kubelet
    ;;
r | restart)
    sudo systemctl restart docker && sudo systemctl restart kubelet
    ;;
*)
    echo "
Usage:

        
"
    ;;
esac
