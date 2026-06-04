# Operations

## Live state reference

At the time this documentation was generated:

- node name: `gpu-node01`
- GPUs visible to Kubernetes: `8`
- running client namespaces: `client01`, `client02`
- monitoring namespace: `monitoring`
- ingress hostnames:
  - `client01.betopialtd.com`
  - `client02.betopialtd.com`
  - `grafana.betopialtd.com`

## Admin entrypoints

### kubectl

Primary cluster administration:

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl describe node gpu-node01
```

### Workspace admin helper

Use [configs/workspaces/workspace-admin.sh](../configs/workspaces/workspace-admin.sh) on the server as `/root/k8s/workspace-admin.sh`.

Supported commands:

```bash
/root/k8s/workspace-admin.sh list
/root/k8s/workspace-admin.sh status client01
/root/k8s/workspace-admin.sh create client03 31003 200Gi
/root/k8s/workspace-admin.sh apply client03
/root/k8s/workspace-admin.sh suspend client01
/root/k8s/workspace-admin.sh resume client01
/root/k8s/workspace-admin.sh terminate client03 --purge
/root/k8s/workspace-admin.sh token client01
/root/k8s/workspace-admin.sh url client01
/root/k8s/workspace-admin.sh logs client01
/root/k8s/workspace-admin.sh grafana
```

## Client lifecycle

### Create

```bash
/root/k8s/workspace-admin.sh create client03 31003 200Gi
```

What it does:

- generates `/root/k8s/client03.yaml`
- generates a Jupyter token
- applies namespace, quota, secret, PVC, deployment, services, ingress
- waits for the deployment rollout

### Suspend

```bash
/root/k8s/workspace-admin.sh suspend client03
```

This scales the deployment to zero while preserving the PVC and namespace.

### Resume

```bash
/root/k8s/workspace-admin.sh resume client03
```

### Delete but keep data

```bash
/root/k8s/workspace-admin.sh terminate client03
```

This removes the runtime objects but leaves the namespace and PVC.

### Delete and purge

```bash
/root/k8s/workspace-admin.sh terminate client03 --purge
```

This also deletes the PVC and namespace.

## Client resource model

Per client:

- CPU request: `8`
- CPU limit: `8`
- Memory request: `24Gi`
- Memory limit: `32Gi`
- GPU limit: `1`
- PVC default: `200Gi`

Quota headroom:

- CPU hard limit: `9`
- memory hard limit: `33Gi`
- pods hard limit: `10`

That extra headroom exists so `cert-manager` can create temporary ACME HTTP-01 solver pods in the namespace.

## Operational checks

Free GPUs:

```bash
kubectl describe node gpu-node01 | sed -n '/Allocated resources:/,/Events:/p'
```

Client inventory:

```bash
kubectl get ns | awk 'NR==1 || $1 ~ /^client[0-9][0-9]$/'
```

Per-client state:

```bash
kubectl get deploy,pod,svc,pvc,ingress,certificate -n client01 -o wide
```

Per-client logs:

```bash
kubectl logs -n client01 deploy/client01-jupyter --tail=200
```

## Backup guidance

For this single-node phase:

- back up `/root/k8s`
- back up `/etc/kubernetes`
- back up `/var/lib/etcd`
- back up persistent workspace data from the local-path storage area
- export important YAML:

```bash
kubectl get all,ingress,pvc,secret,resourcequota,limitrange -A -o yaml > /root/cluster-export.yaml
```

## Go/no-go checks before adding more paying clients

- `nvidia-smi` clean on host
- `kubectl top nodes` and `kubectl top pods -A` working
- `kubectl get certificate -A` shows `READY=True`
- `kubectl describe node gpu-node01` shows `nvidia.com/gpu: 8`
- enough free disk remains for more PVCs
- firewalld rules still allow `80`, `443`, `31001-31008`, `32000`

