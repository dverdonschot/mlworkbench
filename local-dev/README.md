# Local Talos Kubernetes Development Environment

This directory contains scripts for setting up a local Talos Kubernetes cluster using libvirt/virsh.

## Why Talos Linux?

**Talos is a modern, minimal, immutable Linux distribution designed specifically for Kubernetes.**

Key advantages:
- ✅ **Built-in Kubernetes** - No separate k3s/k8s installation needed
- ✅ **API-driven** - No SSH access required, managed via `talosctl`
- ✅ **Immutable** - Secure by default, minimal attack surface
- ✅ **Fast bootstrap** - ~5-7 minutes from VMs to ready cluster
- ✅ **Production parity** - Same OS in development and production

## Prerequisites

### On Bazzite (your system)

Install required tools:

```bash
# Check if libvirt is available
rpm-ostree status

# If not installed, layer libvirt packages
rpm-ostree install libvirt virt-install qemu-kvm

# Or use toolbox/distrobox
toolbox create dev
toolbox enter dev
sudo dnf install -y libvirt virt-install qemu-kvm qemu-img
```

Enable and start libvirt:

```bash
sudo systemctl enable --now libvirtd
sudo usermod -a -G libvirt $(whoami)
# Log out and back in for group changes
```

Install talosctl:

```bash
# Download latest talosctl
curl -sL https://talos.dev/install | sh
```

## Quick Start

### 1. Create Talos VMs

```bash
./setup-talos-vms-disk.sh
```

This creates 3 VMs with:
- 2 vCPU, 8 GB RAM each
- 50GB OS disk (`/dev/vda`)
- 50GB data disk (`/dev/vdb`) for Kubernetes storage
- Talos Linux v1.11.3

**Time**: ~5 minutes (download + VM creation)

### 2. Initialize Talos Cluster

```bash
./talos-cluster-init.sh
```

**Fully automated:**
- Detects VM IPs via DHCP
- Generates Talos configuration (3 control-plane nodes)
- Applies configuration to all nodes
- Configures data disk mounting at `/var/lib/k8s-storage`
- Bootstraps etcd cluster
- Retrieves kubeconfig

**Time**: ~5-7 minutes

### 3. Verify Cluster

```bash
export KUBECONFIG=~/.kube/talos-config
kubectl get nodes
```

Expected output:
```
NAME          STATUS   ROLES           AGE   VERSION
talos-k8s-1   Ready    control-plane   5m    v1.34.1
talos-k8s-2   Ready    control-plane   5m    v1.34.1
talos-k8s-3   Ready    control-plane   5m    v1.34.1
```

All nodes should be `Ready`.

### 4. Deploy Applications

Now you're ready to deploy the full stack:

```bash
cd ../gitops/bootstrap
./bootstrap.sh  # Installs ArgoCD

cd ..
kubectl apply -f argocd-apps/argocd-root-app.yaml  # Deploys everything
```

See: [DEPLOYMENT_GUIDE.md](../DEPLOYMENT_GUIDE.md) for full instructions.

## Talos Commands

### Cluster Management

```bash
# Set talosctl defaults (add to ~/.bashrc)
export TALOSCONFIG=~/.talos-local/talosconfig
export KUBECONFIG=~/.kube/talos-config

# Health check
talosctl --nodes <node-ip> health

# Interactive dashboard
talosctl --nodes <node-ip> dashboard

# View cluster info
talosctl --nodes <node-ip> version
talosctl --nodes <node-ip> get members
```

### Node Operations

```bash
# View logs
talosctl --nodes <node-ip> logs kubelet
talosctl --nodes <node-ip> logs etcd
talosctl --nodes <node-ip> dmesg

# Check services
talosctl --nodes <node-ip> service kubelet status
talosctl --nodes <node-ip> service etcd status

# Reboot node
talosctl --nodes <node-ip> reboot

# Upgrade Talos
talosctl --nodes <node-ip> upgrade \
  --image ghcr.io/siderolabs/installer:v1.11.3
```

### Configuration

```bash
# View node config
talosctl --nodes <node-ip> get machineconfig

# Apply config changes
talosctl --nodes <node-ip> apply-config --file controlplane.yaml

# Edit config
talosctl --nodes <node-ip> edit machineconfig
```

### Storage

```bash
# Check disk usage
talosctl --nodes <node-ip> df

# View mounts
talosctl --nodes <node-ip> mounts | grep k8s-storage

# List disks
talosctl --nodes <node-ip> disks
```

## VM Management

### List VMs

```bash
sudo virsh list --all
```

### Start/Stop VMs

```bash
# Start all
for i in {1..3}; do sudo virsh start talos-k8s-$i; done

# Stop all
for i in {1..3}; do sudo virsh shutdown talos-k8s-$i; done

# Force stop
for i in {1..3}; do sudo virsh destroy talos-k8s-$i; done
```

### Get VM IPs

```bash
# Show DHCP leases
sudo virsh net-dhcp-leases default

# Or check per VM
for i in {1..3}; do
  echo "talos-k8s-$i:"
  sudo virsh domifaddr talos-k8s-$i
done
```

### Delete VMs

```bash
# Delete single VM (with storage)
sudo virsh destroy talos-k8s-1 2>/dev/null || true
sudo virsh undefine talos-k8s-1 --remove-all-storage

# Delete all VMs
for i in {1..3}; do
  sudo virsh destroy talos-k8s-$i 2>/dev/null || true
  sudo virsh undefine talos-k8s-$i --remove-all-storage
done

# Clean up configs
rm -rf ~/.talos-local ~/.kube/talos-config
```

### Start Fresh

```bash
# Destroy VMs
for i in {1..3}; do
  sudo virsh destroy talos-k8s-$i 2>/dev/null || true
  sudo virsh undefine talos-k8s-$i --remove-all-storage
done

# Clean configs
rm -rf ~/.talos-local ~/.kube/talos-config

# Recreate
./setup-talos-vms-disk.sh
./talos-cluster-init.sh
```

## Testing Production Scenarios

### Test Node Failure

```bash
# Simulate node failure
sudo virsh destroy talos-k8s-2

# Watch pods reschedule
kubectl get pods -A -o wide -w

# Bring node back
sudo virsh start talos-k8s-2
```

### Test Etcd Quorum

```bash
# Stop 1 node - cluster should continue (2/3 quorum)
sudo virsh shutdown talos-k8s-3
kubectl get nodes  # Should still work

# Stop 2 nodes - cluster loses quorum
sudo virsh shutdown talos-k8s-2
kubectl get nodes  # Will hang or fail
```

### Test Upgrades

```bash
# Upgrade one node
talosctl --nodes 192.168.122.55 upgrade \
  --image ghcr.io/siderolabs/installer:v1.11.4

# Watch node drain and rejoin
kubectl get nodes -w
```

### Test Storage

```bash
# Create test PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: local-path
EOF

# Check PV created
kubectl get pv,pvc
```

## Storage Configuration

### Data Disks

Each VM has two disks:
- `/dev/vda` (50GB) - OS disk (read-only, immutable)
- `/dev/vdb` (50GB) - Data disk for Kubernetes storage

Data disk is mounted at `/var/lib/k8s-storage` on all nodes.

### StorageClass

The `local-path` StorageClass uses `/var/lib/k8s-storage` for persistent volumes:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
```

### Check Storage Usage

```bash
# Per node
talosctl --nodes <node-ip> df

# Via Kubernetes
kubectl get pv
kubectl get pvc -A
```

## Configuration Files

```
~/.talos-local/
├── controlplane.yaml  # Control plane node config
├── worker.yaml        # Worker node config (unused in 3-CP setup)
└── talosconfig        # talosctl client config (credentials)

~/.kube/
└── talos-config       # kubectl kubeconfig
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Your Host (Bazzite Linux)                              │
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │  libvirt/KVM                                    │    │
│  │                                                  │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────┴──┐ │
│  │  │ talos-k8s-1  │  │ talos-k8s-2  │  │ talos-k8s-3│ │
│  │  │              │  │              │  │            │ │
│  │  │ Control      │  │ Control      │  │ Control    │ │
│  │  │ Plane        │  │ Plane        │  │ Plane      │ │
│  │  │ + etcd       │  │ + etcd       │  │ + etcd     │ │
│  │  │              │  │              │  │            │ │
│  │  │ OS: 50GB     │  │ OS: 50GB     │  │ OS: 50GB   │ │
│  │  │ Data: 50GB   │  │ Data: 50GB   │  │ Data: 50GB │ │
│  │  │ 8GB RAM      │  │ 8GB RAM      │  │ 8GB RAM    │ │
│  │  │ 2 vCPU       │  │ 2 vCPU       │  │ 2 vCPU     │ │
│  │  └──────────────┘  └──────────────┘  └────────────┘ │
│  │         ↑                  ↑                 ↑       │
│  │         └──────────────────┴─────────────────┘       │
│  │              192.168.122.0/24 network                │
│  └──────────────────────────────────────────────────────┘
│                                                          │
│  talosctl ──→ Talos API (secure, mTLS)                 │
│  kubectl  ──→ Kubernetes API                            │
└──────────────────────────────────────────────────────────┘
```

## Troubleshooting

### VMs won't start

```bash
# Check libvirtd status
sudo systemctl status libvirtd

# Check logs
sudo journalctl -u libvirtd -f

# Check VM console
sudo virsh console talos-k8s-1
# Press Ctrl+] to exit
```

### Cluster init fails

```bash
# Check node connectivity
talosctl --nodes 192.168.122.55 version --insecure

# View logs
cat /tmp/talos-apply-1.log
cat /tmp/talos-bootstrap.log

# Start fresh
./talos-cluster-init.sh --clean
```

### Can't access cluster

```bash
# Verify kubeconfig
export KUBECONFIG=~/.kube/talos-config
kubectl cluster-info

# Check node IPs match config
kubectl config view
talosctl --nodes <node-ip> get members
```

### Storage issues

```bash
# Check data disk mounting
talosctl --nodes <node-ip> mounts | grep k8s-storage

# Check PV provisioner
kubectl get pods -n kube-system -l app=local-path-provisioner

# Describe PVC
kubectl describe pvc <pvc-name>
```

## Resource Usage

**VMs (3 nodes):**
- CPU: 2 vCPUs × 3 = 6 vCPUs
- RAM: 8GB × 3 = 24GB
- Disk: 100GB × 3 = 300GB (50GB OS + 50GB data per node)

**Kubernetes Workloads:**
- CPU: ~2-3 cores (peak)
- RAM: ~6-8GB (with observability stack)
- Storage: ~20-30GB (logs, metrics, traces with 7-day retention)

## Production Parity

This local Talos setup mirrors production:
- ✅ Same OS: Talos Linux v1.11.3
- ✅ Same Kubernetes: v1.34.1
- ✅ Same architecture: 3 control-plane nodes with etcd
- ✅ Same storage: Dedicated data disks
- ✅ Immutable infrastructure: Safe testing of updates/reboots

## Next Steps

Once cluster is running:

1. **Bootstrap ArgoCD**: `cd ../gitops/bootstrap && ./bootstrap.sh`
2. **Deploy stack**: `kubectl apply -f ../gitops/argocd-apps/argocd-root-app.yaml`
3. **Access Grafana**: `kubectl port-forward -n monitoring svc/grafana 3000:80`
4. **Test applications**: See [DEPLOYMENT_GUIDE.md](../DEPLOYMENT_GUIDE.md)

## References

- [Talos Documentation](https://www.talos.dev/latest/)
- [Talos on libvirt](https://www.talos.dev/latest/talos-guides/install/virtualized-platforms/libvirt/)
- [Talos API Reference](https://www.talos.dev/latest/reference/api/)
- [Full Deployment Guide](../DEPLOYMENT_GUIDE.md)
