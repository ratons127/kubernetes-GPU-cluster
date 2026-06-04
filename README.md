# Kubernetes GPU Cluster

Production-minded single-node Kubernetes GPU workspace platform for `8 x NVIDIA Tesla P40` on `RHEL 10.1`.

This repository documents the full build that was applied to a fresh server and the resulting operating model:

- Host OS: `Red Hat Enterprise Linux 10.1`
- Kubernetes: `v1.34.8`
- Container runtime: `containerd 2.2.4`
- GPUs: `8 x Tesla P40`, exposed to Kubernetes as `nvidia.com/gpu: 8`
- GPU model: `1 client workspace = 1 full physical GPU`
- Workspace type: `JupyterLab`
- Monitoring: `Prometheus + Grafana + metrics-server + NVIDIA DCGM exporter`
- TLS: `ingress-nginx + cert-manager + Let's Encrypt`

## Current deployed shape

The live cluster documented here was built on `gpu-node01` with public IP `103.149.105.249`.

- `client01.betopialtd.com` and `client02.betopialtd.com` are active GPU workspaces
- `grafana.betopialtd.com` is exposed over HTTPS
- Kubernetes node advertises `nvidia.com/gpu: 8`
- Two GPUs are currently allocated to running client pods; six remain free

## Repository layout

- [docs/01-architecture.md](docs/01-architecture.md): architecture and design decisions
- [docs/02-build-runbook.md](docs/02-build-runbook.md): fresh-server build commands
- [docs/03-operations.md](docs/03-operations.md): day-2 operations and client lifecycle
- [docs/04-monitoring.md](docs/04-monitoring.md): monitoring stack and validation
- [docs/05-troubleshooting.md](docs/05-troubleshooting.md): practical fault guide
- [configs/](configs): sanitized manifests and helper scripts

## Architecture summary

```text
Internet
  |
  +-- 443/80 -> ingress-nginx (hostNetwork on single node)
                   |
                   +-- client01 namespace -> Jupyter workspace -> 1 GPU
                   +-- client02 namespace -> Jupyter workspace -> 1 GPU
                   +-- clientNN namespace -> Jupyter workspace -> 1 GPU
                   +-- monitoring namespace -> Grafana / Prometheus

gpu-node01
  |
  +-- RHEL 10.1
  +-- NVIDIA driver 580.159.04
  +-- containerd + nvidia-container-runtime
  +-- kubeadm single-node control plane
  +-- Calico CNI
  +-- local-path storage
  +-- NVIDIA device plugin
```

## Security notes

This repository intentionally does **not** store:

- live Jupyter tokens
- live Grafana passwords
- private keys or TLS account secrets
- raw per-client `.info` files from the server

Anything sensitive in the live system has been replaced with placeholders in `configs/`.

## Quick status commands

```bash
kubectl get nodes -o wide
kubectl top nodes
kubectl top pods -A
kubectl get pods -A -o wide
kubectl get ingress -A
kubectl get certificate -A
kubectl describe node gpu-node01
nvidia-smi
```

## Rebuild intent

The runbook in this repository is not generic Ubuntu guidance. It reflects the actual build performed on a fresh `RHEL 10.1` server for:

- no MIG
- no GPU time-slicing
- one namespace per client
- one PVC per client
- one full Tesla P40 per client workspace

