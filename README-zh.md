# 部署全新的 K8S 集群

## 使用 Docker 容器，手操部署 K8S Master

Docker 容器的方式（与进程启动类似），将各组件分别启动，完成部署的同时体会 K8S 的各个组件的功能组合与各部件的角色、意义。

具体步骤如下：

1. 运行 `./run.sh init_k8s_on_docker` 命令初始化 K8S 基础环境（内核参数、Docker 环境、生成证书、 Kubeconfig 配置。

## 使用静态 Pod 的方式部署 K8S Master

静态 Pod 的方式通过 kubelet 程序添加 `staticPodPath` 启动项后开启对该路径下 Pod YAML 文件的检测、并自动部署。静态 Pod 以容器组的方式组织 Master 组件（kube-apiserver、kube-controller-manager、kube-scheduler 等），运行的容器组与节点绑定（适合搭建开发或者 k8s 学习环境）。

通过以下简单的两步来完成集群部署（须按步骤进行）

1. 首先运行 `./run.sh init_k8s_static_pod` 命令初始化 K8S 基础环境，包括 内核参数调整、 旧版本 Docker 删除、新版本 Docker 安装等
2. 运行 `./run.sh kstart kubelet_service_unit_init` 命令来初始化并启动 kubelet 服务，这个命令只需要执行一次，之后应该使用 systemd 来管理 kubelet 进程

注释：

`init_k8s_static_pod` 命令主要执行以下几个命令：

```bash
init::all               # 初始化 K8S 基础环境
pki::gen_ca             # 生成 PKI 相关签名证书
kubeconfig::all         # 基于初始化的设置与证书生成对应的 kubeconfig 配置
```

其中 K8S 基础环境的初始化包含以下几步：

```bash
init::sysctl            # 内核参数等相关调整
init::clean_old_docker  # 旧版本 Docker 删除
init::install_docker    # 新版本 Docker 安装
init::kube_env          # 相关环境变量设置（比如 Etcd Master IP、K8S 集群地址等）
init::kube_manifests    # 生成相关 manifests 文件（这种方式通过静态 Pod 来启动 K8S 相关组件，如果通过 Docker 启动则不需要这步）
```