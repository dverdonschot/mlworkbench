# MLWorkbench Deployment Guide

Complete guide for deploying the MLWorkbench Federated Learning Platform on Talos Linux.

---

## Quick Start (30 Minutes Total)

```bash
# 1. Create Talos VMs (5 minutes)
cd /var/home/ewt/mlworkbench/local-dev
./setup-talos-vms-disk.sh

# 2. Initialize Talos cluster (5-7 minutes)
./talos-cluster-init.sh

# 3. Set kubeconfig
export KUBECONFIG=~/.kube/talos-config

# 4. Bootstrap ArgoCD (3 minutes)
cd ../gitops/bootstrap
./bootstrap-talos.sh

# 5. Create sealed secrets (10-15 minutes - ONE TIME SETUP)
# See sealed-secrets.md for detailed instructions
# Install kubeseal CLI and create all 11 sealed secrets
# Commit them to your Git repository

# 6. Update repository URLs (1 minute)
cd ../argocd-apps
# Edit all YAML files: replace YOUR_USERNAME with your GitHub username
find . -name '*.yaml' -exec sed -i 's|YOUR_USERNAME|dverdonschot|g' {} +

# 7. Deploy all services (5-10 minutes)
kubectl apply -f root-app.yaml

# 8. Watch deployment
kubectl get applications -n argocd -w
```

**Total Time**: ~30-35 minutes from zero to fully operational cluster with secure secrets!

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Phase 1: Create VMs](#phase-1-create-vms)
3. [Phase 2: Initialize Cluster](#phase-2-initialize-cluster)
4. [Phase 3: Bootstrap ArgoCD](#phase-3-bootstrap-argocd)
5. [Phase 4: Deploy Services](#phase-4-deploy-services)
6. [Phase 5: Verify Deployment](#phase-5-verify-deployment)
7. [Accessing Services](#accessing-services)
8. [Troubleshooting](#troubleshooting)
9. [Next Steps](#next-steps)

---

## Prerequisites

### System Requirements

- **CPU**: 8+ cores (6 for VMs + 2 for host)
- **RAM**: 32GB+ (24GB for VMs + 8GB for host)
- **Disk**: 350GB free space
- **OS**: Fedora 43 (or any Linux with KVM support)

### Required Tools

Check if you have everything:

```bash
# Check versions
virsh --version          # libvirt (any recent version)
talosctl version        # >=1.8.0
kubectl version         # >=1.28.0
yq --version            # v4.x
```

### Install Missing Tools

**libvirt/KVM (Fedora 43):**
```bash
sudo dnf install -y libvirt virt-install qemu-kvm qemu-img zstd wget
sudo systemctl enable --now libvirtd
sudo usermod -a -G libvirt $(whoami)
# Log out and back in for group changes
```

**talosctl:**
```bash
curl -sL https://talos.dev/install | sh
```

**kubectl:**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

**yq (YAML processor):**
```bash
sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
sudo chmod +x /usr/local/bin/yq
```

---

## Phase 1: Create VMs

### Step 1: Navigate to local-dev directory

```bash
cd /var/home/ewt/mlworkbench/local-dev
```

### Step 2: Run VM creation script

```bash
./setup-talos-vms-disk.sh
```

**What this does:**
1. Downloads Talos Linux v1.11.3 disk image (~170MB)
2. Creates 3 VMs with libvirt/KVM
3. Each VM gets:
   - 2 vCPUs
   - 8GB RAM
   - 50GB OS disk (`/dev/vda`)
   - 50GB data disk (`/dev/vdb`)
4. Starts all VMs

**Expected output:**
```
[INFO] Checking dependencies...
[INFO] All dependencies found.
[INFO] Checking for Talos disk image...
[INFO] Downloading Talos v1.11.3 disk image...
[INFO] Extracting Talos disk image...
[INFO] Creating 3 VMs...
[INFO] Creating VM: talos-k8s-1
[INFO] Creating VM: talos-k8s-2
[INFO] Creating VM: talos-k8s-3
✓ All VMs created successfully!

Next step: Run the cluster initialization script
  ./talos-cluster-init.sh
```

**Verify VMs are running:**
```bash
sudo virsh list

# Expected output:
# Id   Name          State
# -----------------------------
# 1    talos-k8s-1   running
# 2    talos-k8s-2   running
# 3    talos-k8s-3   running
```

**Time**: ~5 minutes (depends on download speed)

---

## Phase 2: Initialize Cluster

### Step 1: Run cluster initialization

```bash
./talos-cluster-init.sh
```

**What this does (fully automated):**
1. Detects VM IP addresses from DHCP
2. Generates Talos configuration for 3-node control-plane
3. Applies configuration to all nodes
4. Configures data disk mounting at `/var/lib/k8s-storage`
5. Bootstraps etcd cluster
6. Waits for cluster to form
7. Retrieves kubeconfig
8. Verifies cluster health

**Expected output:**
```
======================================================================
Talos Kubernetes Cluster Initialization
======================================================================

[INFO] Detecting Talos VM IP addresses...
[INFO] Detected nodes:
  - talos-k8s-1: 192.168.122.55
  - talos-k8s-2: 192.168.122.56
  - talos-k8s-3: 192.168.122.57

[INFO] Generating Talos configuration...
[INFO] Applying Talos configuration to all nodes...
[INFO] Bootstrapping etcd on first node...
[INFO] Waiting for cluster to form...
[INFO] Retrieving kubeconfig...
[INFO] Verifying cluster...

✅ Talos cluster successfully initialized!

Cluster details:
  - Name: talos-local
  - Nodes: 3 control-plane nodes
  - Node IPs: 192.168.122.55, 192.168.122.56, 192.168.122.57
  - Kubeconfig: ~/.kube/talos-config
  - Talos config: ~/.talos-local/talosconfig
```

**Time**: ~5-7 minutes

### Step 2: Set kubeconfig environment variable

```bash
export KUBECONFIG=~/.kube/talos-config
```

**Add to shell profile (optional but recommended):**
```bash
echo 'export KUBECONFIG=~/.kube/talos-config' >> ~/.bashrc
# or for zsh:
echo 'export KUBECONFIG=~/.kube/talos-config' >> ~/.zshrc
```

### Step 3: Verify cluster

```bash
kubectl get nodes
```

**Expected output:**
```
NAME            STATUS   ROLES           AGE   VERSION
talos-xxx-xxx   Ready    control-plane   5m    v1.34.1
talos-xxx-xxx   Ready    control-plane   5m    v1.34.1
talos-xxx-xxx   Ready    control-plane   5m    v1.34.1
```

All nodes should show `STATUS: Ready`.

**Check system pods:**
```bash
kubectl get pods -n kube-system
```

All pods should be `Running` or `Completed`.

---

## Phase 3: Bootstrap ArgoCD

### Step 1: Navigate to bootstrap directory

```bash
cd ../gitops/bootstrap
```

### Step 2: Run bootstrap script

```bash
./bootstrap-talos.sh
```

**What this does:**
1. Checks prerequisites (kubectl, talosctl)
2. Verifies Talos cluster is accessible
3. Installs Gateway API CRDs (required for Envoy Gateway)
4. Creates `argocd` namespace
5. Deploys ArgoCD
6. Retrieves admin password
7. Displays access instructions

**Expected output:**
```
==========================================
  Talos GitOps Bootstrap
  MLWorkbench Federated Learning Platform
==========================================

[INFO] Checking prerequisites...
✓ All prerequisites met

[INFO] Checking Talos Kubernetes cluster...
✓ Talos Kubernetes cluster detected
  Nodes: 3

[INFO] Installing Gateway API CRDs...
✓ Gateway API CRDs installed successfully

[INFO] Creating argocd namespace...
✓ Namespace created

[INFO] Deploying ArgoCD...
[INFO] Waiting for ArgoCD to be ready (this may take 2-3 minutes)...
✓ ArgoCD deployed successfully

==========================================
ArgoCD Credentials:
Username: admin
Password: <generated-password>
==========================================

Password saved to: /tmp/argocd-admin-password.txt
```

**Time**: ~3 minutes

### Step 3: Save ArgoCD credentials

```bash
# View password
cat /tmp/argocd-admin-password.txt

# Or save to a secure location
cp /tmp/argocd-admin-password.txt ~/argocd-password.txt
chmod 600 ~/argocd-password.txt
```

---

## Phase 4: Deploy Services

### Step 1: Create Sealed Secrets

**CRITICAL:** Before deploying services, you must create all sealed secrets to avoid using hardcoded passwords.

See **[sealed-secrets.md](sealed-secrets.md)** for complete instructions.

**Quick summary:**
```bash
# 1. Install kubeseal CLI (if not already installed)
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.34.0/kubeseal-0.34.0-linux-amd64.tar.gz
tar -xzf kubeseal-0.34.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# 2. Follow sealed-secrets.md to create all 11 sealed secrets
# Each secret is created with kubeseal and saved to gitops/sealed-secrets/

# 3. Commit sealed secrets to Git
git add gitops/sealed-secrets/
git commit -m "Add sealed secrets for all services"
git push
```

**Time**: ~10-15 minutes (one-time setup)

### Step 2: Update repository URLs

Before deploying, you need to update the repository URLs in ArgoCD Application definitions.

```bash
cd ../argocd-apps
```

**Option 1: Automated replacement (if using your own fork)**

```bash
# Replace YOUR_USERNAME with your actual GitHub username
find . -name '*.yaml' -exec sed -i 's|YOUR_USERNAME|dverdonschot|g' {} +

# Verify changes
git diff
```

**Option 2: Manual editing**

Edit each `*.yaml` file and replace:
- `YOUR_USERNAME` → your GitHub username/organization

**Files to update:**
- `root-app.yaml`
- `argocd.yaml`
- `external-secrets.yaml`
- `cert-manager.yaml`
- `envoy-gateway.yaml`
- `tailscale.yaml`
- `metallb.yaml`
- `local-path-provisioner.yaml`
- `airflow.yaml`
- `mlflow.yaml`
- `minio.yaml`
- `postgresql.yaml`
- `redis.yaml`
- `monitoring.yaml`
- `loki.yaml`

### Step 2: Commit changes (optional but recommended)

```bash
git add .
git commit -m "Configure ArgoCD apps for MLWorkbench deployment"
git push
```

### Step 3: Deploy root application

```bash
kubectl apply -f root-app.yaml
```

**Expected output:**
```
application.argoproj.io/root created
```

### Step 4: Watch deployment progress

**Option 1: kubectl watch**
```bash
kubectl get applications -n argocd -w
```

**Option 2: ArgoCD UI**

1. Port-forward to ArgoCD server:
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   ```

2. Open browser: https://localhost:8080

3. Login:
   - Username: `admin`
   - Password: (from `/tmp/argocd-admin-password.txt`)

4. You should see all applications deploying

**Expected applications:**
- `argocd` (self-managed)
- `external-secrets`
- `cert-manager`
- `envoy-gateway`
- `tailscale`
- `metallb`
- `local-path-provisioner`
- `airflow`
- `mlflow`
- `minio`
- `postgresql`
- `redis`
- `monitoring`
- `loki`

**Time**: 5-10 minutes for all services to become healthy

---

## Phase 5: Verify Deployment

### Check all applications in ArgoCD

```bash
kubectl get applications -n argocd
```

**Expected output:**
```
NAME                   SYNC STATUS   HEALTH STATUS
argocd                 Synced        Healthy
external-secrets       Synced        Healthy
cert-manager          Synced        Healthy
envoy-gateway         Synced        Healthy
tailscale             Synced        Healthy
metallb               Synced        Healthy
local-path-provisioner Synced        Healthy
airflow               Synced        Healthy
mlflow                Synced        Healthy
minio                 Synced        Healthy
postgresql            Synced        Healthy
redis                 Synced        Healthy
monitoring            Synced        Healthy
loki                  Synced        Healthy
```

All should show:
- **SYNC STATUS**: `Synced`
- **HEALTH STATUS**: `Healthy`

### Check all pods

```bash
kubectl get pods -A
```

All pods should be `Running` or `Completed` (no `CrashLoopBackOff`, `Error`, or `Pending`).

### Check storage

```bash
kubectl get pv
kubectl get pvc -A
```

Persistent Volumes should be `Bound` to Persistent Volume Claims.

### Check services

```bash
kubectl get svc -A
```

Look for LoadBalancer services with external IPs assigned by MetalLB.

---

## Accessing Services

### ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open: https://localhost:8080
- Username: `admin`
- Password: (from `/tmp/argocd-admin-password.txt`)

### Airflow UI

```bash
kubectl port-forward svc/airflow-webserver -n airflow 8081:8080
```

Open: http://localhost:8081
- Username: `admin`
- Password: `admin` (default, change in production)

### MLflow UI

```bash
kubectl port-forward svc/mlflow -n mlflow 5000:5000
```

Open: http://localhost:5000

### MinIO Console

```bash
kubectl port-forward svc/minio-console -n minio 9001:9001
```

Open: http://localhost:9001
- Username: `minio`
- Password: `minio123`

### Grafana (Monitoring)

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
```

Open: http://localhost:3000
- Username: `admin`
- Password: `admin` (default, will prompt to change)

---

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
talosctl --talosconfig ~/.talos-local/talosconfig version --insecure --nodes 192.168.122.55

# View logs
cat /tmp/talos-apply-1.log
cat /tmp/talos-bootstrap.log

# Start fresh
for i in {1..3}; do
  sudo virsh destroy talos-k8s-$i 2>/dev/null || true
  sudo virsh undefine talos-k8s-$i --remove-all-storage
done
rm -rf ~/.talos-local ~/.kube/talos-config

# Re-run scripts
./setup-talos-vms-disk.sh
./talos-cluster-init.sh
```

### ArgoCD application not syncing

```bash
# Check application details
kubectl describe application <app-name> -n argocd

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Force sync
kubectl patch application <app-name> -n argocd --type merge --patch '{"operation":{"sync":{}}}'

# Or via ArgoCD UI: Click app → Sync → Synchronize
```

### Pods not starting

```bash
# Describe pod
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

### Storage issues

```bash
# Check StorageClass
kubectl get storageclass

# Check if local-path is default
kubectl get storageclass local-path -o yaml

# Check data disk mounting on Talos nodes
talosctl --talosconfig ~/.talos-local/talosconfig mounts --nodes 192.168.122.55 | grep k8s-storage

# Expected: /dev/vdb mounted at /var/lib/k8s-storage
```

### Network issues

```bash
# Check MetalLB
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system

# Check Gateway API
kubectl get gatewayclasses
kubectl get gateways -A
```

---

## Next Steps

### 1. Configure Secrets

The bootstrap script created a `mlworkbench` namespace. You need to create secrets:

```bash
# Create secrets for ML workloads
kubectl create secret generic mlworkbench-env \
  --from-literal=HUGGINGFACE_TOKEN="your-token" \
  --from-literal=AWS_ACCESS_KEY_ID="minio" \
  --from-literal=AWS_SECRET_ACCESS_KEY="minio123" \
  --namespace=mlworkbench
```

### 2. Deploy Custom DAGs to Airflow

```bash
# Option 1: ConfigMap (for testing)
kubectl create configmap airflow-dags \
  --from-file=dags/ \
  --namespace=airflow

# Option 2: GitSync (recommended for production)
# Edit gitops/argocd-apps/airflow.yaml
# Enable gitSync and point to your DAGs repository
```

### 3. Create Federated Learning Applications

Create services in `gitops/namespaces/mlworkbench/`:
- FL Coordinator
- FL Worker Pool
- Image Recognition Pipeline
- API Gateway
- Model Registry

### 4. Set up Ingress (Optional)

Create HTTPRoute resources for external access:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: airflow-route
  namespace: airflow
spec:
  parentRefs:
    - name: mlworkbench-gateway
      namespace: envoy-gateway-system
  hostnames:
    - airflow.mlworkbench.local
  rules:
    - backendRefs:
        - name: airflow-webserver
          port: 8080
```

### 5. Configure Monitoring Dashboards

Access Grafana and import dashboards:
- Kubernetes Cluster Monitoring
- Airflow Metrics
- Custom FL Metrics

### 6. Plan OVH Cloud Migration

Once everything works locally, follow the OVH migration plan in `INFRASTRUCTURE_OUTLINE.md`.

---

## Useful Commands

### Talos Management

```bash
# Set aliases
export TALOSCONFIG=~/.talos-local/talosconfig
alias talos='talosctl --talosconfig $TALOSCONFIG'

# Health check
talos health --nodes 192.168.122.55

# Dashboard
talos dashboard --nodes 192.168.122.55

# Logs
talos logs kubelet --nodes 192.168.122.55
talos logs etcd --nodes 192.168.122.55
```

### Kubernetes Management

```bash
# Quick checks
kubectl get nodes
kubectl get pods -A
kubectl get applications -n argocd

# Resource usage
kubectl top nodes
kubectl top pods -A

# Describe resources
kubectl describe node <node-name>
kubectl describe pod <pod-name> -n <namespace>
```

### ArgoCD Management

```bash
# List apps
kubectl get applications -n argocd

# Sync app
kubectl patch application <app-name> -n argocd --type merge --patch '{"operation":{"sync":{}}}'

# Get app details
kubectl get application <app-name> -n argocd -o yaml
```

---

## Cleanup

### Delete all applications

```bash
kubectl delete -f gitops/argocd-apps/root-app.yaml
```

### Destroy VMs

```bash
cd /var/home/ewt/mlworkbench/local-dev

for i in {1..3}; do
  sudo virsh destroy talos-k8s-$i 2>/dev/null || true
  sudo virsh undefine talos-k8s-$i --remove-all-storage
done
```

### Clean up configs

```bash
rm -rf ~/.talos-local ~/.kube/talos-config
```

---

## Resources

- **Talos Documentation**: https://www.talos.dev/
- **ArgoCD Documentation**: https://argo-cd.readthedocs.io/
- **Apache Airflow**: https://airflow.apache.org/docs/
- **MLflow**: https://mlflow.org/docs/
- **Envoy Gateway**: https://gateway.envoyproxy.io/

---

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review `INFRASTRUCTURE_OUTLINE.md` for architecture details
3. Check logs: `kubectl logs <pod-name> -n <namespace>`
4. Check events: `kubectl get events -n <namespace> --sort-by='.lastTimestamp'`

---

**🎉 Congratulations! Your MLWorkbench Federated Learning Platform is ready!**
