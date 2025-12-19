# NFS Shared Storage Implementation Plan

## Goal
Add NFS shared storage to the MLWorkbench cluster so stateful workloads (PostgreSQL, MinIO, etc.) can:
- Run on any node (not tied to local storage)
- Survive cluster destruction and recreation
- Use storage that persists on the Fedora host

## Overview

```
┌─────────────────────────────────────────┐
│     Fedora Host (Your Workstation)      │
│  ┌───────────────────────────────────┐  │
│  │  /srv/nfs/mlworkbench             │  │
│  │  (NFS Export)                     │  │
│  └───────────────────────────────────┘  │
│              │                           │
│              │ NFS Protocol              │
└──────────────┼───────────────────────────┘
               │
    ┌──────────┼──────────┐
    │          │          │
┌───▼───┐  ┌──▼────┐  ┌──▼────┐
│ Node1 │  │ Node2 │  │ Node3 │
│       │  │       │  │       │
│ NFS   │  │ NFS   │  │ NFS   │
│Client │  │Client │  │Client │
└───┬───┘  └───┬───┘  └───┬───┘
    │          │          │
    └──────────┼──────────┘
               │
    ┌──────────▼──────────┐
    │ nfs-subdir-external-│
    │    provisioner      │
    │ (Creates PVs/PVCs)  │
    └─────────────────────┘
               │
    ┌──────────▼──────────┐
    │   PostgreSQL Pod    │
    │   MinIO Pod         │
    │   etc.              │
    └─────────────────────┘
```

## Implementation Steps

### Phase 1: Host NFS Server Setup (5 minutes)

**File:** `local-dev/setup-nfs-server.sh`

**What it does:**
1. Install `nfs-utils` on Fedora host
2. Create `/srv/nfs/mlworkbench` directory
3. Configure `/etc/exports` with:
   - Export: `/srv/nfs/mlworkbench`
   - Network: `192.168.122.0/24` (libvirt network)
   - Options: `rw,sync,no_subtree_check,no_root_squash,insecure`
4. Configure firewall rules for NFS
5. Enable and start NFS server
6. Export shares

**Run once:**
```bash
sudo ./local-dev/setup-nfs-server.sh
```

---

### Phase 2: Talos NFS Client Support (OPTIONAL - Check First)

**Check if NFS support is already in Talos:**
```bash
talosctl -n 192.168.122.55 get extensions
```

**If NFS extension is missing:**

You'll need to create a custom Talos image with NFS client support. This requires:
- Fork/update your talos-images repository
- Add NFS client kernel modules
- Build custom Talos image
- Update VM creation script to use custom image

**Alternative (Simpler):** Recent Talos versions (v1.8+) include NFS support by default. Verify your Talos version:
```bash
talosctl -n 192.168.122.55 version
```

If version >= 1.8, you likely already have NFS support. **Skip custom image building.**

---

### Phase 3: Deploy NFS Provisioner via ArgoCD (10 minutes)

**Files to create:**

#### 1. `gitops/argocd-apps/nfs-provisioner.yaml`
```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nfs-subdir-external-provisioner
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner
    targetRevision: 4.0.18
    chart: nfs-subdir-external-provisioner
    helm:
      values: |
        nfs:
          server: 192.168.122.1  # CHANGE TO YOUR HOST IP
          path: /srv/nfs/mlworkbench

        storageClass:
          name: nfs-client
          defaultClass: false
          archiveOnDelete: true  # Moves deleted PVCs to archived-* folder

        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi

  destination:
    server: https://kubernetes.default.svc
    namespace: nfs-provisioner

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Get your host IP:**
```bash
ip addr show | grep "192.168.122"
# Usually: 192.168.122.1
```

---

### Phase 4: Update Storage Classes for Stateful Apps (15 minutes)

Update applications to use `nfs-client` storage class instead of `local-path`:

#### 1. **PostgreSQL** - `gitops/argocd-apps/postgresql.yaml`
```yaml
persistence:
  enabled: true
  size: 20Gi
  storageClass: nfs-client  # Changed from: local-path
```

#### 2. **Redis** - `gitops/argocd-apps/redis.yaml`
```yaml
master:
  persistence:
    enabled: true
    size: 5Gi
    storageClass: nfs-client  # Changed from: local-path
```

#### 3. **MinIO** - `gitops/argocd-apps/minio.yaml`
```yaml
persistence:
  enabled: true
  size: 50Gi
  storageClass: nfs-client  # Changed from: local-path
```

#### 4. **Monitoring (Prometheus)** - Keep on local-path (metrics don't need to persist)
```yaml
# No change - monitoring data can be ephemeral
storageClass: local-path
```

#### 5. **Loki** - Optional, use NFS if you want to keep logs
```yaml
persistence:
  enabled: true
  size: 10Gi
  storageClass: nfs-client  # Or keep local-path if logs are ephemeral
```

---

### Phase 5: Testing & Validation (10 minutes)

**Test 1: Verify NFS server from host**
```bash
showmount -e localhost
# Should show: /srv/nfs/mlworkbench 192.168.122.0/24
```

**Test 2: Deploy NFS provisioner**
```bash
kubectl apply -f gitops/argocd-apps/nfs-provisioner.yaml
kubectl get pods -n nfs-provisioner -w
```

**Test 3: Verify storage class**
```bash
kubectl get storageclass
# Should show: nfs-client
```

**Test 4: Create test PVC**
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-nfs-claim
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-client
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc test-nfs-claim
# Should show: Bound

# Check on host
ls -la /srv/nfs/mlworkbench/
# Should see: default-test-nfs-claim-pvc-xxxxx/

# Cleanup
kubectl delete pvc test-nfs-claim
```

**Test 5: Redeploy PostgreSQL**
```bash
# Delete existing PostgreSQL PVC (WARNING: destroys data!)
kubectl delete pvc -n databases data-postgresql-0

# ArgoCD will recreate with NFS storage
kubectl get pvc -n databases -w
```

---

## File Changes Summary

### New Files:
1. `local-dev/setup-nfs-server.sh` - NFS server setup script
2. `gitops/argocd-apps/nfs-provisioner.yaml` - ArgoCD app for NFS provisioner

### Modified Files:
1. `gitops/argocd-apps/postgresql.yaml` - Change storageClass to nfs-client
2. `gitops/argocd-apps/redis.yaml` - Change storageClass to nfs-client
3. `gitops/argocd-apps/minio.yaml` - Change storageClass to nfs-client
4. `gitops/argocd-apps/loki.yaml` - (Optional) Change storageClass to nfs-client

### Documentation Updates:
1. `DEPLOYMENT_GUIDE.md` - Add Phase 2.5: Setup NFS Storage (before Phase 3)
2. `README.md` - Mention NFS shared storage in features

---

## Benefits After Implementation

✅ **Cluster Portability**: Destroy and recreate cluster anytime, data persists on host
✅ **Pod Mobility**: Pods can run on any node, not tied to specific node storage
✅ **Easy Backups**: Just backup `/srv/nfs/mlworkbench` on your host
✅ **Development Friendly**: Power off all VMs for gaming, data remains safe
✅ **ReadWriteMany**: Multiple pods can share same volume (useful for DAGs, configs)

---

## Migration Path (Existing Data)

If you have existing data on local-path storage:

**Option 1: Fresh start (easiest)**
```bash
# Backup any important data first
# Delete cluster
# Setup NFS
# Recreate cluster with NFS storage
```

**Option 2: Migrate data**
```bash
# 1. Setup NFS provisioner alongside local-path
# 2. Create new PVCs with nfs-client storage class
# 3. Use a migration pod to copy data from old PVC to new PVC
# 4. Update app to use new PVC
# 5. Delete old PVC
```

---

## Troubleshooting

### NFS mount fails
```bash
# Check NFS server on host
sudo systemctl status nfs-server
sudo exportfs -v

# Check from Talos node
talosctl -n 192.168.122.55 get mounts
```

### Permission denied errors
```bash
# Make sure export uses no_root_squash
# Check /etc/exports on host

# Make NFS directory permissive
sudo chmod 777 /srv/nfs/mlworkbench
```

### Firewall blocking NFS
```bash
# On Fedora host
sudo firewall-cmd --list-all
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=rpc-bind
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --reload
```

---

## Time Estimate

- Phase 1: 5 minutes (NFS server setup)
- Phase 2: 0-30 minutes (likely already supported, otherwise needs custom image)
- Phase 3: 10 minutes (deploy provisioner)
- Phase 4: 15 minutes (update apps)
- Phase 5: 10 minutes (testing)

**Total: ~40 minutes** (assuming NFS already supported in Talos)

---

## Next Steps When You're Home

1. Run `setup-nfs-server.sh` on your Fedora host
2. Verify Talos has NFS support (likely yes if v1.8+)
3. Deploy NFS provisioner via ArgoCD
4. Update storage classes for PostgreSQL, Redis, MinIO
5. Test with a fresh cluster deployment
6. Enjoy gaming without worrying about your cluster! 🎮
