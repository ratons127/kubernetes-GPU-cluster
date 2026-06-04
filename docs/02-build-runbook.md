# Fresh Server Build Runbook

This section reconstructs the build performed on a fresh `RHEL 10.1` server.

## 1. Base host preparation

Set hostname:

```bash
hostnamectl set-hostname gpu-node01
```

Register the server and enable required repositories:

```bash
subscription-manager register
subscription-manager attach --auto
subscription-manager repos \
  --enable=rhel-10-for-x86_64-baseos-rpms \
  --enable=rhel-10-for-x86_64-appstream-rpms \
  --enable=rhel-10-for-x86_64-extensions-rpms \
  --enable=codeready-builder-for-rhel-10-x86_64-rpms
dnf makecache
```

Optional but used on the live host:

```bash
dnf install -y epel-release
```

Open required services and ports:

```bash
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-port=31001-31008/tcp
firewall-cmd --permanent --add-port=32000/tcp
firewall-cmd --reload
```

## 2. Disable swap and set kernel prerequisites

Create kernel module file:

```bash
cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
```

Create sysctl file:

```bash
cat >/etc/sysctl.d/99-kubernetes-cri.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system
```

Disable swap:

```bash
swapoff -a
sed -i 's|^UUID=.* swap .*|# &|' /etc/fstab
```

## 3. Install containerd

Add Docker CE repo and install containerd:

```bash
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y containerd.io
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
systemctl enable --now containerd
```

## 4. Install Kubernetes tools

Add Kubernetes repo:

```bash
cat >/etc/yum.repos.d/kubernetes.repo <<'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/repodata/repomd.xml.key
EOF
```

Install packages:

```bash
dnf install -y kubelet kubeadm kubectl cri-tools
systemctl enable kubelet
```

Install Helm:

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## 5. Install NVIDIA driver and toolkit

Add the NVIDIA CUDA repo:

```bash
dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel10/x86_64/cuda-rhel10.repo
dnf makecache
```

Install driver and toolkit packages used on the live host:

```bash
dnf install -y \
  nvidia-driver \
  nvidia-driver-cuda \
  kmod-nvidia-latest-dkms \
  nvidia-container-toolkit
```

Configure containerd for NVIDIA runtime:

```bash
nvidia-ctk runtime configure --runtime=containerd
systemctl restart containerd
```

The live host uses `nvidia` as the default `containerd` runtime:

```toml
[plugins."io.containerd.cri.v1.runtime".containerd]
  default_runtime_name = "nvidia"

[plugins."io.containerd.cri.v1.runtime".containerd.runtimes.nvidia]
  [plugins."io.containerd.cri.v1.runtime".containerd.runtimes.nvidia.options]
    BinaryName = "/usr/bin/nvidia-container-runtime"
```

Validate on the host:

```bash
nvidia-smi -L
```

Expected result on the live server: `8` Tesla P40 GPUs.

## 6. Initialize Kubernetes

Use the kubeadm config in [configs/cluster/kubeadm-config.yaml](../configs/cluster/kubeadm-config.yaml):

```bash
mkdir -p /root/k8s
cp configs/cluster/kubeadm-config.yaml /root/k8s/kubeadm-config.yaml
kubeadm init --config /root/k8s/kubeadm-config.yaml
```

Configure kubectl:

```bash
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown "$(id -u)":"$(id -g)" $HOME/.kube/config
```

Allow the control-plane node to run workloads:

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

## 7. Install Calico

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.3/manifests/calico.yaml
```

## 8. Install local-path storage

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

## 9. Install NVIDIA device plugin

Add repo and install chart:

```bash
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo update
kubectl create namespace nvidia-device-plugin
helm upgrade --install nvidia-device-plugin nvdp/nvidia-device-plugin \
  --namespace nvidia-device-plugin
```

Create `RuntimeClass`:

```bash
kubectl apply -f configs/cluster/runtimeclass-nvidia.yaml
```

Validate:

```bash
kubectl describe node gpu-node01 | grep -A10 Capacity
```

Expected:

```text
nvidia.com/gpu: 8
```

## 10. Install ingress-nginx

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
kubectl create namespace ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.hostNetwork=true \
  --set controller.service.type=ClusterIP \
  --set controller.dnsPolicy=ClusterFirstWithHostNet
```

The live cluster serves ingress directly from host `80/443`.

## 11. Install cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
kubectl create namespace cert-manager
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.20.2 \
  --set crds.enabled=true
```

Because this single-node environment had pod-network egress issues for ACME, the live cluster also patched `cert-manager` to use host networking:

```bash
kubectl apply -f configs/cluster/cert-manager-hostnet-patch.yaml
kubectl rollout restart deploy/cert-manager -n cert-manager
```

Install the production issuer:

```bash
kubectl apply -f configs/cluster/clusterissuer-letsencrypt-prod.yaml
```

## 12. Install monitoring

Add repos:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add dcgm-exporter https://nvidia.github.io/dcgm-exporter/helm-charts
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update
```

Create namespace:

```bash
kubectl create namespace monitoring
```

Install metrics-server:

```bash
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  -f configs/monitoring/metrics-server-values.yaml
```

The live cluster required additional patches because kubelet scraping only became reliable when `metrics-server` used `hostNetwork` and a different secure port:

```bash
kubectl apply -f configs/monitoring/metrics-server-hostnet-patch.yaml
kubectl apply -f configs/monitoring/metrics-server-port-patch.yaml
kubectl patch deployment metrics-server -n kube-system --type=json --patch-file configs/monitoring/metrics-server-jsonpatch.json
kubectl rollout restart deployment metrics-server -n kube-system
```

Install kube-prometheus-stack:

```bash
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f configs/monitoring/kube-prometheus-stack-values.yaml
```

Install dcgm-exporter:

```bash
helm upgrade --install dcgm-exporter dcgm-exporter/dcgm-exporter \
  --namespace monitoring \
  -f configs/monitoring/dcgm-exporter-values.yaml
```

## 13. Expose Grafana

Apply:

```bash
kubectl apply -f configs/monitoring/grafana-ingress.yaml
```

DNS required:

```text
grafana.betopialtd.com -> 103.149.105.249
```

## 14. Provision client workspaces

Copy helper scripts:

```bash
mkdir -p /root/k8s
cp configs/workspaces/provision-client.sh /root/k8s/
cp configs/workspaces/workspace-admin.sh /root/k8s/
chmod +x /root/k8s/provision-client.sh /root/k8s/workspace-admin.sh
```

Create a workspace:

```bash
/root/k8s/workspace-admin.sh create client01 31001 200Gi
```

## 15. Build validation

Host validation:

```bash
nvidia-smi -L
```

Cluster validation:

```bash
kubectl get nodes -o wide
kubectl describe node gpu-node01 | grep -A10 Capacity
kubectl top nodes
kubectl top pods -A
kubectl get ingress -A
kubectl get certificate -A
```

