# GPU Time-Slicing

This cluster was later converted from full physical GPU allocation to NVIDIA device-plugin time-slicing.

## Live setting

- physical GPUs: `8 x Tesla P40`
- time-slicing replicas per GPU: `4`
- advertised Kubernetes GPU capacity: `32`

Formula:

```text
8 physical GPUs x 4 replicas = 32 schedulable nvidia.com/gpu slots
```

## Important behavior change

Before:

- `nvidia.com/gpu: 1` meant one full physical GPU

After:

- `nvidia.com/gpu: 1` means one shared GPU slot

This was done intentionally with `renameByDefault: false` so the existing workspace manifests could continue to use the same resource name.

## NVIDIA caveats

Time-slicing is not isolation.

- GPU memory is not hard-partitioned
- workloads on the same GPU share a fault domain
- a bad workload can affect others on that same GPU
- the setting applies node-wide in this single-node design

## Applied config

Reference file:

- [configs/cluster/nvidia-device-plugin-timeslicing-4-values.yaml](../configs/cluster/nvidia-device-plugin-timeslicing-4-values.yaml)

Live server copy:

- `/root/k8s/nvidia-device-plugin-timeslicing-4-values.yaml`

## Apply on the server

```bash
helm upgrade --install nvidia-device-plugin nvdp/nvidia-device-plugin \
  --namespace nvidia-device-plugin \
  -f /root/k8s/nvidia-device-plugin-timeslicing-4-values.yaml
```

## Validation

Check advertised capacity:

```bash
kubectl get node gpu-node01 -o jsonpath='{.status.capacity.nvidia\.com/gpu} {.status.allocatable.nvidia\.com/gpu}'; echo
```

Expected:

```text
32 32
```

Check node description:

```bash
kubectl describe node gpu-node01 | sed -n '/Capacity:/,/Allocatable:/p'
```

Expected:

```text
nvidia.com/gpu: 32
```

## Functional validation that was performed

The live cluster was validated by scheduling `10` GPU pods simultaneously on the single node, which is more than the physical GPU count of `8`. All ten pods reached `Running`, and a test pod confirmed:

```text
torch.cuda.is_available() = True
torch.cuda.device_count() = 1
GPU name = Tesla P40
```

## Operational note

If you want to go back to full physical GPU allocation later, reapply the original device plugin values without the `sharing.timeSlicing` block and wait for the DaemonSet to roll out.

