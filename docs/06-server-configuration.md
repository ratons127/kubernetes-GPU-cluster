# Server Configuration

This document captures the host-level server configuration that was applied on the live `gpu-node01` system. It is separate from Kubernetes YAML because the platform depends on both:

- RHEL host configuration
- package repositories
- NVIDIA driver and container runtime
- firewall rules
- Kubernetes bootstrap

## Live server baseline

At documentation time, the live host is:

- Hostname: `gpu-node01`
- Public IP: `103.149.105.249`
- OS: `Red Hat Enterprise Linux 10.1 (Coughlan)`
- Kernel: `6.12.0-211.18.1.el10_2.x86_64`

## 1. Host identity and subscription

Set hostname:

```bash
hostnamectl set-hostname gpu-node01
hostnamectl
```

Register the server with Red Hat:

```bash
subscription-manager register
subscription-manager attach --auto
subscription-manager repos \
  --enable=rhel-10-for-x86_64-baseos-rpms \
  --enable=rhel-10-for-x86_64-appstream-rpms \
  --enable=rhel-10-for-x86_64-extensions-rpms \
  --enable=rhel-10-for-x86_64-highavailability-rpms \
  --enable=codeready-builder-for-rhel-10-x86_64-rpms
dnf makecache
```

Live enabled Red Hat repositories:

- `rhel-10-for-x86_64-baseos-rpms`
- `rhel-10-for-x86_64-appstream-rpms`
- `rhel-10-for-x86_64-extensions-rpms`
- `rhel-10-for-x86_64-highavailability-rpms`
- `codeready-builder-for-rhel-10-x86_64-rpms`

## 2. Third-party repo files

These repo files are present on the live host.

### NVIDIA CUDA repo

File: [configs/system/cuda-rhel10.repo](../configs/system/cuda-rhel10.repo)

Create with:

```bash
cat >/etc/yum.repos.d/cuda-rhel10.repo <<'EOF'
[cuda-rhel10-x86_64]
name=cuda-rhel10-x86_64
baseurl=https://developer.download.nvidia.com/compute/cuda/repos/rhel10/x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://developer.download.nvidia.com/compute/cuda/repos/rhel10/x86_64/CDF6BA43.pub
EOF
```

### Docker CE repo

File: [configs/system/docker-ce.repo](../configs/system/docker-ce.repo)

Create with:

```bash
cat >/etc/yum.repos.d/docker-ce.repo <<'EOF'
[docker-ce-stable]
name=Docker CE Stable - $basearch
baseurl=https://download.docker.com/linux/rhel/10/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/rhel/gpg
EOF
```

### Kubernetes repo

File: [configs/system/kubernetes.repo](../configs/system/kubernetes.repo)

Create with:

```bash
cat >/etc/yum.repos.d/kubernetes.repo <<'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
```

## 3. Kernel modules and sysctl

### Modules loaded for Kubernetes networking

File: [configs/system/k8s.conf](../configs/system/k8s.conf)

Apply with:

```bash
cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter
```

### Sysctl settings

File: [configs/system/99-kubernetes-cri.conf](../configs/system/99-kubernetes-cri.conf)

Apply with:

```bash
cat >/etc/sysctl.d/99-kubernetes-cri.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system
```

## 4. Swap configuration

The live host has swap disabled.

Immediate disable:

```bash
swapoff -a
```

Persist by commenting the swap line in `/etc/fstab`.

Example command:

```bash
sed -i 's|^UUID=.* swap .*|# &|' /etc/fstab
```

Validate:

```bash
swapon --show
cat /etc/fstab
```

## 5. Base package installation

Recommended base packages for this build:

```bash
dnf install -y \
  vim git curl wget jq tar unzip python3 python3-pip \
  dnf-plugins-core epel-release
```

## 6. Container runtime installation

Install containerd:

```bash
dnf install -y containerd.io
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
systemctl enable --now containerd
```

## 7. NVIDIA driver and toolkit installation

Live installed NVIDIA-related packages:

- `kmod-nvidia-latest-dkms`
- `nvidia-driver`
- `nvidia-driver-cuda`
- `nvidia-container-toolkit`
- `libnvidia-container-tools`
- `libnvidia-container1`

Install with:

```bash
dnf install -y \
  nvidia-driver \
  nvidia-driver-cuda \
  kmod-nvidia-latest-dkms \
  nvidia-container-toolkit
```

Configure NVIDIA runtime for containerd:

```bash
nvidia-ctk runtime configure --runtime=containerd
systemctl restart containerd
```

Validate:

```bash
nvidia-smi
nvidia-smi -L
```

Expected live result: `8 x Tesla P40`.

## 8. containerd configuration

The live `containerd` configuration sets `nvidia` as the default runtime.

Reference file:

- [configs/system/containerd-config-snippet.toml](../configs/system/containerd-config-snippet.toml)

The critical section is:

```toml
[plugins."io.containerd.cri.v1.runtime".containerd]
  default_runtime_name = "nvidia"

[plugins."io.containerd.cri.v1.runtime".containerd.runtimes.nvidia]
  runtime_type = "io.containerd.runc.v2"

[plugins."io.containerd.cri.v1.runtime".containerd.runtimes.nvidia.options]
  BinaryName = "/usr/bin/nvidia-container-runtime"
  SystemdCgroup = true
```

Validate:

```bash
grep -n -A10 -B3 'nvidia' /etc/containerd/config.toml
systemctl status containerd
```

## 9. Kubernetes packages

Install:

```bash
dnf install -y kubelet kubeadm kubectl cri-tools kubernetes-cni
systemctl enable --now kubelet
```

Live installed versions:

- `kubeadm 1.34.8`
- `kubectl 1.34.8`
- `kubelet 1.34.8`
- `cri-tools 1.34.0`
- `kubernetes-cni 1.7.1`

## 10. Helm installation

Install Helm:

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

## 11. kubeadm bootstrap

Use [configs/cluster/kubeadm-config.yaml](../configs/cluster/kubeadm-config.yaml):

```bash
mkdir -p /root/k8s
cp configs/cluster/kubeadm-config.yaml /root/k8s/kubeadm-config.yaml
kubeadm init --config /root/k8s/kubeadm-config.yaml
```

Then:

```bash
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown "$(id -u)":"$(id -g)" $HOME/.kube/config
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

## 12. Firewall configuration

The live host has `firewalld` enabled and active.

Enable and start:

```bash
systemctl enable --now firewalld
```

Open services:

```bash
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-service=cockpit
firewall-cmd --permanent --add-service=dhcpv6-client
```

Open port ranges used in this design:

```bash
firewall-cmd --permanent --add-port=31001-31008/tcp
firewall-cmd --permanent --add-port=32000/tcp
firewall-cmd --reload
```

Live open services:

- `cockpit`
- `dhcpv6-client`
- `http`
- `https`
- `ssh`

Live open ports:

- `31001-31008/tcp`

Note:

- Grafana NodePort `32000/tcp` was opened during deployment. Reapply it if you rebuild from scratch.

## 13. System services that must stay enabled

Validate with:

```bash
systemctl is-enabled containerd kubelet firewalld
systemctl is-active containerd kubelet firewalld
```

Live state:

- `containerd`: enabled, active
- `kubelet`: enabled, active
- `firewalld`: enabled, active

## 14. Exact validation commands

Use these to verify the host layer before moving to client workloads:

```bash
cat /etc/redhat-release
uname -r
hostnamectl
nvidia-smi -L
systemctl status containerd
systemctl status kubelet
systemctl status firewalld
firewall-cmd --list-services
firewall-cmd --list-ports
kubectl get nodes -o wide
kubectl describe node gpu-node01 | grep -A10 Capacity
```

## 15. Recommended rebuild order

1. Set hostname and network.
2. Register RHEL and enable repos.
3. Install base tools.
4. Disable swap.
5. Apply kernel modules and sysctl.
6. Install containerd.
7. Install NVIDIA driver and toolkit.
8. Configure `containerd` for NVIDIA runtime.
9. Install Kubernetes packages and Helm.
10. Run `kubeadm init`.
11. Install Calico.
12. Install local-path storage.
13. Install NVIDIA device plugin.
14. Install ingress-nginx.
15. Install cert-manager and ClusterIssuer.
16. Install monitoring stack.
17. Provision client workspaces.

