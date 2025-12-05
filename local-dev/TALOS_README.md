# Talos Kubernetes Cluster Setup

Automated local development cluster using Talos Linux and libvirt/KVM.

## Quick Start

```bash
# 1. Create VMs (if not already done)
./setup-talos-vms.sh

# 2. Initialize cluster (fully automated)
./talos-cluster-init.sh

# 3. Start using Kubernetes
export KUBECONFIG=~/.kube/talos-config
kubectl get nodes
```

## What This Does

The `talos-cluster-init.sh` script fully automates:

1. **Detect VM IPs** - Finds your 3 Talos VMs via DHCP leases
2. **Generate config** - Creates Talos configuration for 3-node control-plane cluster
3. **Apply config** - Pushes configuration to all nodes (handles maintenance mode)
4. **Bootstrap etcd** - Initializes the etcd cluster on the first node
5. **Wait for cluster** - Monitors health until cluster forms
6. **Get kubeconfig** - Retrieves and saves kubectl configuration
7. **Verify** - Checks all nodes are Ready

**Time**: ~5-7 minutes total

## Current VMs

Your Talos VMs are already running:

```
talos-k8s-1: 192.168.122.55
talos-k8s-2: 192.168.122.56
talos-k8s-3: 192.168.122.57
```

## Troubleshooting Last Failure

**Problem**: Nodes were in maintenance mode, empty talosconfig

**Solution**: The updated script:
- Uses `--insecure` flag for initial config application (maintenance mode requirement)
- Generates proper talosconfig with credentials
- Logs all operations to `/tmp/talos-*.log` for debugging
- Has better error handling and status reporting

## Clean Start

If you want to start fresh with new configuration:

```bash
./talos-cluster-init.sh --clean
```

This removes `~/.talos-local/` and regenerates all configs.

## Manual Debugging

If the script fails, check these:

```bash
# 1. Verify VMs are running
sudo virsh list

# 2. Check node connectivity
talosctl --nodes 192.168.122.55 version --insecure

# 3. View logs
cat /tmp/talos-apply-1.log
cat /tmp/talos-bootstrap.log

# 4. Check existing config
ls -la ~/.talos-local/
```

## After Cluster Is Ready

### Helpful Aliases

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
export KUBECONFIG=~/.kube/talos-config
alias talos='talosctl --talosconfig ~/.talos-local/talosconfig --nodes 192.168.122.55'
alias talos-all='talosctl --talosconfig ~/.talos-local/talosconfig --nodes 192.168.122.55,192.168.122.56,192.168.122.57'
```

### Common Talos Commands

```bash
# Cluster health
talos health

# Interactive dashboard
talos dashboard

# View logs
talos logs kubelet
talos logs etcd
talos dmesg

# Check services
talos service kubelet status
talos service etcd status

# Reboot a node
talos reboot

# Upgrade Talos
talos upgrade --image ghcr.io/siderolabs/installer:v1.11.3
```

### Deploy Your Applications

```bash
# Set kubeconfig
export KUBECONFIG=~/.kube/talos-config

# Verify cluster
kubectl get nodes
kubectl get pods -A

# Deploy something
kubectl apply -f your-manifests.yaml

# Or use GitOps
cd ../gitops/bootstrap
./bootstrap.sh
```

## VM Management

```bash
# List VMs
sudo virsh list --all

# Start/stop VMs
sudo virsh start talos-k8s-1
sudo virsh shutdown talos-k8s-1

# Destroy everything and start over
for i in {1..3}; do
  sudo virsh destroy talos-k8s-$i
  sudo virsh undefine talos-k8s-$i --remove-all-storage
done
rm -rf ~/.talos-local ~/.kube/talos-config

# Recreate
./setup-talos-vms.sh
./talos-cluster-init.sh
```

## Why Talos vs k3s/Flatcar?

**Advantages**:
- ✅ **Built-in Kubernetes** - No separate install needed
- ✅ **API-driven** - No SSH required, everything via `talosctl`
- ✅ **Immutable** - Secure by default, minimal attack surface
- ✅ **Faster bootstrap** - ~5 minutes vs ~15 minutes for Flatcar+k3s
- ✅ **Production-ready** - Same OS in dev and production

**Talos Philosophy**:
- Minimal: No shell, no SSH, no package manager
- Secure: All configuration via API with mTLS
- Predictable: Immutable OS, declarative config
- Cloud-native: Designed specifically for Kubernetes

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

## Configuration Files

```
~/.talos-local/
├── controlplane.yaml  # Control plane node config
├── worker.yaml        # Worker node config (unused in 3-CP setup)
└── talosconfig        # talosctl client config (credentials)

~/.kube/
└── talos-config       # kubectl kubeconfig
```

## Next Steps After Cluster Init

1. **Deploy monitoring** (Prometheus, Grafana, Loki)
2. **Deploy ArgoCD** for GitOps
3. **Deploy your applications**
4. **Test disaster recovery** (destroy a node, watch cluster heal)

## Resources

- [Talos Documentation](https://www.talos.dev/latest/)
- [Talos on libvirt](https://www.talos.dev/latest/talos-guides/install/virtualized-platforms/libvirt/)
- [Talos API Reference](https://www.talos.dev/latest/reference/api/)
