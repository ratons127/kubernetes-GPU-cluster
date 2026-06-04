# Architecture

## Goal

Turn one physical GPU server into a single-node Kubernetes platform where each client gets:

- one isolated namespace
- one JupyterLab workspace
- one persistent volume
- exactly one full `Tesla P40`
- no host root access

## Host profile

- Hostname: `gpu-node01`
- OS: `Red Hat Enterprise Linux 10.1 (Coughlan)`
- Kernel: `6.12.0-211.18.1.el10_2.x86_64`
- CPU allocatable: `88`
- RAM allocatable: `263359016Ki`
- GPUs allocatable: `8`
- Container runtime: `containerd://2.2.4`
- Kubernetes: `v1.34.8`

## GPU model

This cluster uses the simplest isolation model:

- each client pod requests `limits.nvidia.com/gpu: 1`
- Kubernetes schedules that pod only if one full GPU is available
- no MIG
- no time-slicing
- no GPU oversubscription

That means the cluster supports a maximum of `8` active client GPU workspaces at one time.

## Component roles

### RHEL 10.1

Provides:

- base OS
- kernel and kmod compatibility
- firewalld
- SELinux baseline
- systemd

### NVIDIA driver

Installed on the host so the kernel exposes all physical GPUs:

- package branch used: `580.159.04`
- host validation command: `nvidia-smi -L`

### NVIDIA Container Toolkit

Enables containers to use GPUs through `containerd` and the `nvidia-container-runtime`.

### Kubernetes

Single-node control plane installed with `kubeadm`:

- kube-apiserver
- etcd
- controller-manager
- scheduler
- kubelet
- kube-proxy

### Calico

Provides pod networking.

### NVIDIA device plugin

Advertises GPU resources into Kubernetes. This is the component that makes the node expose:

```text
nvidia.com/gpu: 8
```

### local-path storage

Provides simple persistent storage for this first phase. It is appropriate for a single-node test/staging platform.

### ingress-nginx

Handles:

- HTTPS entry for Jupyter workspaces
- HTTPS entry for Grafana
- direct binding to host `80/443` using `hostNetwork`

### cert-manager

Handles:

- Let's Encrypt ACME HTTP-01 validation
- certificate issuance for per-client subdomains
- certificate issuance for Grafana

### Prometheus / Grafana / DCGM exporter / metrics-server

Provide:

- cluster monitoring
- GPU telemetry
- resource usage
- dashboards

## Namespace model

One client per namespace:

- `client01`
- `client02`
- `client03`
- `client04`
- `client05`
- `client06`
- `client07`
- `client08`

Each namespace contains:

- `ResourceQuota`
- `LimitRange`
- `Secret` with Jupyter token
- `PersistentVolumeClaim`
- `Deployment`
- `ClusterIP Service`
- `NodePort Service`
- `Ingress`
- `Certificate`

## Client package model

Current package shape:

- GPU: `1 x Tesla P40`
- CPU request/limit: `8`
- Memory request: `24Gi`
- Memory limit: `32Gi`
- Storage: `200Gi` default
- Access: `JupyterLab`

Quota headroom was deliberately raised slightly above the workspace allocation so that temporary ACME solver pods can still be created during certificate issuance.

## Access model

Primary access:

- `https://clientNN.betopialtd.com/lab?token=<token>`

Fallback access:

- `http://103.149.105.249:310NN/lab?token=<token>`

Grafana:

- `https://grafana.betopialtd.com`

## Why this design

This design was chosen because it is:

- simple enough to bootstrap on one node
- strict about one full GPU per client
- compatible with WHMCS-style provisioning later
- safer than handing out host SSH or full VMs in phase 1

