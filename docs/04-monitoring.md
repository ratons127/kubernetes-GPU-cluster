# Monitoring

## Installed components

The live cluster uses:

- `metrics-server`
- `kube-prometheus-stack`
- `dcgm-exporter`

Installed Helm releases on the live server:

- `cert-manager` `v1.20.2`
- `dcgm-exporter` `4.8.2`
- `ingress-nginx` `1.15.1`
- `kube-prometheus-stack` `86.1.1`
- `metrics-server` `0.8.0`
- `nvidia-device-plugin` `0.18.1`

## Purpose of each component

### metrics-server

Provides data for:

- `kubectl top nodes`
- `kubectl top pods -A`

### kube-prometheus-stack

Provides:

- Prometheus
- Alertmanager
- Grafana
- node-exporter
- kube-state-metrics

### dcgm-exporter

Provides NVIDIA GPU metrics into Prometheus.

## Live validation commands

```bash
kubectl get pods -n monitoring
kubectl get servicemonitor -n monitoring
kubectl top nodes
kubectl top pods -A
nvidia-smi
```

GPU metrics reachability:

```bash
kubectl get svc -n monitoring dcgm-exporter
kubectl get pods -n monitoring -l app.kubernetes.io/name=dcgm-exporter -o wide
```

## Grafana

Service exposure on the live cluster:

- NodePort fallback on `32000`
- HTTPS ingress on `grafana.betopialtd.com`

Grafana ingress manifest:

- [configs/monitoring/grafana-ingress.yaml](../configs/monitoring/grafana-ingress.yaml)

## Metrics that matter

Track at minimum:

- GPU utilization
- GPU memory used
- GPU temperature
- GPU power draw
- node CPU
- node RAM
- pod CPU and RAM
- running client pods
- PVC usage
- pod restart counts

## Known implementation details

### metrics-server fix

The live cluster did not work with a default metrics-server installation. It required:

- `hostNetwork: true`
- `dnsPolicy: ClusterFirstWithHostNet`
- `--kubelet-insecure-tls`
- secure port changed from `10250` to `4443`

Relevant files:

- [configs/monitoring/metrics-server-values.yaml](../configs/monitoring/metrics-server-values.yaml)
- [configs/monitoring/metrics-server-hostnet-patch.yaml](../configs/monitoring/metrics-server-hostnet-patch.yaml)
- [configs/monitoring/metrics-server-port-patch.yaml](../configs/monitoring/metrics-server-port-patch.yaml)
- [configs/monitoring/metrics-server-jsonpatch.json](../configs/monitoring/metrics-server-jsonpatch.json)

### cert-manager fix

The live cluster also required `cert-manager` to use `hostNetwork` for reliable Let's Encrypt access in this environment.

Relevant file:

- [configs/cluster/cert-manager-hostnet-patch.yaml](../configs/cluster/cert-manager-hostnet-patch.yaml)

## Example checks

Node usage:

```bash
kubectl top nodes
```

Example live output at documentation time:

```text
NAME         CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
gpu-node01   454m         0%       5569Mi          2%
```

Node GPU capacity:

```bash
kubectl describe node gpu-node01 | grep -A10 Capacity
```

Expected:

```text
nvidia.com/gpu: 8
```

