# Troubleshooting

## NVIDIA driver does not detect Tesla P40

Checks:

```bash
lspci | grep -i nvidia
nvidia-smi
journalctl -k | grep -i nvidia
dnf list installed | grep nvidia
```

Focus areas:

- BIOS `Above 4G Decoding`
- GPU power and seating
- matching kernel and DKMS state
- repo access for driver packages

## Kubernetes does not show `nvidia.com/gpu`

Checks:

```bash
kubectl get pods -n nvidia-device-plugin
kubectl logs -n nvidia-device-plugin ds/nvidia-device-plugin
kubectl describe node gpu-node01 | grep -A10 Capacity
grep -n -A6 -B3 'nvidia' /etc/containerd/config.toml
```

Common causes:

- NVIDIA driver missing on host
- `nvidia-container-runtime` not configured
- device plugin not running

## Pod is stuck in `Pending`

Checks:

```bash
kubectl describe pod -n client01 <pod-name>
```

Common causes:

- `Insufficient nvidia.com/gpu`
- quota too small
- PVC not bound
- image pull issue

## Jupyter cannot see the GPU

Checks inside the pod:

```bash
kubectl exec -n client01 deploy/client01-jupyter -- nvidia-smi
kubectl exec -n client01 deploy/client01-jupyter -- python -c "import torch; print(torch.cuda.is_available()); print(torch.cuda.device_count())"
```

Common causes:

- missing `limits.nvidia.com/gpu: 1`
- no `runtimeClassName: nvidia`
- container image and driver mismatch

## `kubectl top` does not work

Checks:

```bash
kubectl get apiservices | grep metrics
kubectl get pods -n kube-system | grep metrics-server
kubectl logs -n kube-system deploy/metrics-server
```

In this environment, the working fix was:

- `hostNetwork: true`
- `dnsPolicy: ClusterFirstWithHostNet`
- `--kubelet-insecure-tls`
- secure port `4443`

## Let's Encrypt certificate stays pending

Checks:

```bash
kubectl get certificate -A
kubectl get order -A
kubectl get challenge -A
kubectl describe certificate -n <namespace> <name>
Resolve-DnsName <host>
curl -I http://<host>/
```

Common causes observed on the live cluster:

- public DNS record missing
- public `80/443` blocked outside the host
- namespace quota too strict for ACME solver pods
- cert-manager pod cannot reach the internet from pod network

## Grafana or Jupyter URL is unreachable

Checks:

```bash
kubectl get ingress -A
kubectl get svc -A
kubectl get pods -n ingress-nginx -o wide
firewall-cmd --list-services
firewall-cmd --list-ports
```

In this build, ingress works because:

- `ingress-nginx` runs on `hostNetwork`
- host firewalld allows `http` and `https`

## GPU memory full

A client can still exhaust all `24GB` on its assigned P40. Kubernetes only controls GPU count, not in-GPU memory behavior.

Checks:

```bash
nvidia-smi
kubectl exec -n client01 deploy/client01-jupyter -- nvidia-smi
```

## Cleanup leftovers from validation

The live cluster still contains a `gpu-validation` namespace with completed test pods.

Clean it when no longer needed:

```bash
kubectl delete namespace gpu-validation
```

