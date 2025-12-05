# MLWorkbench Infrastructure - Federated Learning Platform
## Local Development Setup with Talos Linux on virsh/KVM

This infrastructure is adapted from the proven mlworkbench-com setup, using:
- **Talos Linux** - Immutable Kubernetes OS
- **ArgoCD** - GitOps continuous delivery
- **Foundational services**: Tailscale, External Secrets, Envoy Gateway, cert-manager
- **ML Platform**: Airflow + Flower for federated learning orchestration

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Why Talos Linux?](#why-talos-linux)
3. [Prerequisites](#prerequisites)
4. [Quick Start](#quick-start)
5. [Layer 0: Virtualization (virsh/KVM)](#layer-0-virtualization-virshkvm)
6. [Layer 1: Talos Kubernetes Cluster](#layer-1-talos-kubernetes-cluster)
7. [Layer 2: Foundational Services](#layer-2-foundational-services)
8. [Layer 3: ML Platform Services](#layer-3-ml-platform-services)
9. [Layer 4: Federated Learning Applications](#layer-4-federated-learning-applications)
10. [Deployment Guide](#deployment-guide)
11. [OVH Cloud Migration Plan](#ovh-cloud-migration-plan)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Infrastructure Layers                        │
├─────────────────────────────────────────────────────────────────┤
│ Layer 0: Virtualization (virsh/KVM)                             │
│   - 3 Talos VMs (control-plane nodes)                           │
│   - 50GB OS disk + 50GB data disk per node                      │
│   - libvirt default network (192.168.122.0/24)                  │
├─────────────────────────────────────────────────────────────────┤
│ Layer 1: Kubernetes Cluster (Talos v1.11.3)                     │
│   - 3 control-plane nodes (scheduling enabled)                  │
│   - Kubernetes v1.34.1                                           │
│   - etcd cluster (3-node quorum)                                │
├─────────────────────────────────────────────────────────────────┤
│ Layer 2: Foundational Services (GitOps)                         │
│   - ArgoCD (self-managed GitOps)                                │
│   - Tailscale (VPN mesh network)                                │
│   - External Secrets Operator (secrets sync)                    │
│   - Envoy Gateway (modern ingress)                              │
│   - cert-manager (TLS certificates)                             │
│   - local-path-provisioner (storage)                            │
│   - MetalLB (load balancer)                                     │
├─────────────────────────────────────────────────────────────────┤
│ Layer 3: ML Platform Services                                   │
│   - Apache Airflow (workflow orchestration)                     │
│   - Flower (Celery monitoring + FL framework)                   │
│   - MLflow (experiment tracking)                                │
│   - PostgreSQL (metadata)                                       │
│   - Redis (caching, message broker)                             │
│   - MinIO (S3-compatible object storage)                        │
│   - Prometheus + Grafana (monitoring)                           │
│   - Loki (log aggregation)                                      │
├─────────────────────────────────────────────────────────────────┤
│ Layer 4: Federated Learning Applications                        │
│   - FL Coordinator (orchestrate FL rounds)                      │
│   - FL Worker Pool (distributed training)                       │
│   - Image Recognition Pipeline                                  │
│   - Model Registry                                              │
│   - Dataset Management Service                                  │
│   - API Gateway (external access)                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## Why Talos Linux?

**Talos Linux is a modern, minimal, immutable Linux distribution designed specifically for Kubernetes.**

### Key Advantages

✅ **Production Parity**: Identical local and production environments
✅ **Built-in Kubernetes**: No separate k3s/k8s installation needed
✅ **API-driven**: No SSH access required, managed via `talosctl`
✅ **Immutable**: Secure by default, minimal attack surface
✅ **Fast bootstrap**: ~5-7 minutes from VMs to ready cluster
✅ **Proven**: Successfully used in mlworkbench-com production

### vs. Other Distributions

| Feature | Talos | k3s | kubeadm |
|---------|-------|-----|---------|
| Setup Time | 5-7 min | 10-15 min | 20-30 min |
| SSH Access | ❌ (API only) | ✅ | ✅ |
| OS Updates | Atomic | Manual | Manual |
| Security | High | Medium | Medium |
| Production Ready | ✅ | ✅ | ✅ |

---

## Prerequisites

### System Requirements

**Local Development (Fedora 43 with KVM):**
- CPU: 8+ cores (6 vCPUs for VMs + host)
- RAM: 32GB+ (24GB for VMs + 8GB for host)
- Disk: 350GB free (300GB for VMs + overhead)
- OS: Fedora 43 (or any Linux with KVM support)

### Required Tools

```bash
# Check versions
virsh --version          # libvirt (any recent version)
talosctl version        # >=1.8.0
kubectl version         # >=1.28.0
argocd version          # >=2.9.0 (optional)
yq --version            # v4.x
```

### Install Missing Tools

**libvirt/KVM (Fedora 43):**
```bash
# Install virtualization packages
sudo dnf install -y libvirt virt-install qemu-kvm qemu-img

# Enable and start libvirtd
sudo systemctl enable --now libvirtd

# Add user to libvirt group
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

**argocd CLI (optional):**
```bash
curl -sSL https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 -o argocd
chmod +x argocd
sudo mv argocd /usr/local/bin/
```

---

## Quick Start

### Complete Setup (5 commands, ~15 minutes)

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

# 5. Deploy all services via GitOps (2-5 minutes)
kubectl apply -f ../argocd-apps/root-app.yaml
```

**Total time: ~15-20 minutes** from zero to fully operational cluster with all services.

---

## Layer 0: Virtualization (virsh/KVM)

### VM Configuration (Proven from mlworkbench)

This configuration has been tested and works perfectly for Kubernetes workloads.

```yaml
nodes:
  count: 3
  role: control-plane  # All nodes are control-plane (no dedicated workers)

  resources:
    vcpu: 2
    memory: 8GB  # 8388608 KiB

  disks:
    os_disk:
      device: /dev/vda
      size: 50GB
      type: qcow2
      purpose: Talos OS (immutable)

    data_disk:
      device: /dev/vdb
      size: 50GB
      type: qcow2
      purpose: Kubernetes persistent storage
      mount: /var/lib/k8s-storage

  network:
    type: libvirt default (NAT)
    range: 192.168.122.0/24
    dhcp: enabled
    mac_pattern: 52:54:00:aa:bb:0{1,2,3}
```

### Total Resources

- **vCPUs**: 6 (2 × 3 nodes)
- **RAM**: 24GB (8GB × 3 nodes)
- **Storage**: 300GB (100GB × 3 nodes)

### Network Topology

```
┌──────────────────────────────────────────────────────┐
│  Your Host (Fedora 43)                               │
│                                                       │
│  ┌─────────────────────────────────────────────┐    │
│  │  libvirt/KVM                                 │    │
│  │                                               │    │
│  │  ┌────────────┐  ┌────────────┐  ┌─────────┴┐   │
│  │  │ talos-k8s-1│  │ talos-k8s-2│  │ talos-k8s-3│  │
│  │  │192.168.122 │  │192.168.122 │  │192.168.122 │  │
│  │  │    .55     │  │    .56     │  │    .57     │  │
│  │  │            │  │            │  │            │  │
│  │  │ OS: 50GB   │  │ OS: 50GB   │  │ OS: 50GB   │  │
│  │  │ Data: 50GB │  │ Data: 50GB │  │ Data: 50GB │  │
│  │  │ 8GB RAM    │  │ 8GB RAM    │  │ 8GB RAM    │  │
│  │  │ 2 vCPU     │  │ 2 vCPU     │  │ 2 vCPU     │  │
│  │  └────────────┘  └────────────┘  └────────────┘  │
│  │         ↑               ↑               ↑         │
│  │         └───────────────┴───────────────┘         │
│  │           192.168.122.0/24 network                │
│  └───────────────────────────────────────────────────┘
│                                                       │
│  talosctl ──→ Talos API (secure, mTLS)              │
│  kubectl  ──→ Kubernetes API                         │
└───────────────────────────────────────────────────────┘
```

---

## Layer 1: Talos Kubernetes Cluster

### Cluster Configuration

```yaml
cluster_name: talos-local
kubernetes_version: v1.34.1
talos_version: v1.11.3

control_plane:
  count: 3
  allow_scheduling: true  # No dedicated workers, all nodes run workloads
  endpoints:
    - 192.168.122.55:6443
    - 192.168.122.56:6443
    - 192.168.122.57:6443

etcd:
  mode: embedded
  nodes: 3
  quorum: 2  # Tolerates 1 node failure

storage:
  data_disk: /dev/vdb
  mount_point: /var/lib/k8s-storage
  filesystem: xfs
```

### Node Details

| Node | IP | Role | vCPU | RAM | OS Disk | Data Disk |
|------|---|------|------|-----|---------|-----------|
| talos-k8s-1 | 192.168.122.55 | control-plane | 2 | 8GB | 50GB | 50GB |
| talos-k8s-2 | 192.168.122.56 | control-plane | 2 | 8GB | 50GB | 50GB |
| talos-k8s-3 | 192.168.122.57 | control-plane | 2 | 8GB | 50GB | 50GB |

### Files Generated

```
~/.talos-local/
├── controlplane.yaml   # Control plane node config
├── worker.yaml         # Worker node config (unused)
└── talosconfig         # talosctl client config (credentials)

~/.kube/
└── talos-config        # kubectl kubeconfig
```

---

## Layer 2: Foundational Services

All services deployed via **ArgoCD** using GitOps pattern.

### 1. ArgoCD - GitOps Controller

**Purpose**: Declarative continuous delivery for Kubernetes

```yaml
namespace: argocd
version: v2.9+
components:
  - argocd-server (UI + API)
  - argocd-repo-server (Git sync)
  - argocd-application-controller (reconciliation)
  - argocd-dex-server (SSO)

access:
  ui: https://localhost:8080 (port-forward)
  cli: argocd (optional)

deployment_pattern: app-of-apps
  # root-app.yaml defines all other applications
  # Self-healing: auto-sync from Git
```

### 2. Tailscale - VPN Mesh Network

**Purpose**: Secure remote access and multi-cloud connectivity

```yaml
namespace: tailscale
deployment: subnet-router
features:
  - Advertise Kubernetes pod network
  - Access from dev machines
  - No port forwarding needed
  - End-to-end encryption

use_cases:
  - Remote cluster access
  - OVH cloud ↔ local connectivity
  - Secure API endpoints
```

### 3. External Secrets Operator

**Purpose**: Sync secrets from external providers to Kubernetes

```yaml
namespace: external-secrets
version: 0.19.2
backends:
  - Infisical (self-hosted, primary)
  - HashiCorp Vault (optional)
  - AWS Secrets Manager (OVH cloud)

components:
  - External Secrets Operator
  - ClusterSecretStore (defines backends)
  - ExternalSecret resources (per namespace)
```

### 4. Envoy Gateway - Modern Ingress

**Purpose**: Advanced API gateway and ingress controller

```yaml
namespace: envoy-gateway-system
version: v1.2.3
based_on: Gateway API v1.2.1
features:
  - HTTP/gRPC routing
  - Rate limiting
  - Authentication/Authorization
  - WebSocket support
  - mTLS
  - Observability (metrics, traces)

use_cases:
  - API endpoints for FL coordinator
  - Model serving endpoints
  - Real-time WebSocket for training updates
```

### 5. cert-manager - TLS Certificates

**Purpose**: Automated certificate management

```yaml
namespace: cert-manager
issuers:
  - letsencrypt-prod (Let's Encrypt)
  - selfsigned (development)

certificates:
  - *.mlworkbench.local (wildcard for all services)
  - Per-service certificates
```

### 6. MetalLB - Load Balancer

**Purpose**: Bare-metal load balancer for LoadBalancer services

```yaml
namespace: metallb-system
ip_pool: 192.168.122.200-192.168.122.250
mode: L2 (layer 2)

use_cases:
  - Expose Envoy Gateway with external IP
  - Expose Airflow UI
  - Local development LoadBalancer support
```

### 7. local-path-provisioner - Storage

**Purpose**: Dynamic persistent volume provisioning

```yaml
namespace: kube-system
storage_class: local-path (default)
path: /var/lib/k8s-storage  # Data disk mount
reclaim_policy: Delete
volume_binding: WaitForFirstConsumer

use_cases:
  - PostgreSQL data
  - Redis persistence
  - MLflow artifacts
  - Airflow logs
```

---

## Layer 3: ML Platform Services

### 1. Apache Airflow - Workflow Orchestration

**Purpose**: Orchestrate ML pipelines and federated learning rounds

```yaml
namespace: airflow
version: 2.8+
executor: KubernetesExecutor  # Or CeleryExecutor

components:
  webserver:
    replicas: 1
    resources:
      cpu: 1
      memory: 2Gi
    port: 8080

  scheduler:
    replicas: 1
    resources:
      cpu: 1
      memory: 2Gi

  workers:  # If using CeleryExecutor
    replicas: 2-5 (autoscaling)
    resources:
      cpu: 2
      memory: 4Gi

  postgresql:
    # Or external PostgreSQL
    storage: 20Gi

  redis:  # For CeleryExecutor
    # Or external Redis
    storage: 5Gi

ingress: airflow.mlworkbench.local

dags:
  sync_method: GitSync
  repo: https://github.com/YOUR_ORG/mlworkbench-dags.git
  branch: main
  sync_interval: 60s
```

**Example DAGs for Federated Learning:**
```python
# dag_federated_training.py
- Task 1: Initialize FL round
- Task 2: Select clients (workers)
- Task 3: Distribute global model
- Task 4: Wait for local training (parallel)
- Task 5: Aggregate model updates (FedAvg)
- Task 6: Update global model
- Task 7: Evaluate on test set
- Task 8: Log metrics to MLflow
- Task 9: Trigger next round or complete
```

### 2. Flower (Celery + FL Framework)

**Purpose**: Monitor Celery workers + Federated Learning framework

```yaml
namespace: airflow  # or dedicated namespace
purpose_1: Celery worker monitoring (if using CeleryExecutor)
purpose_2: Federated learning framework (Flower FL)

# Flower for Celery (monitoring)
flower_celery:
  replicas: 1
  resources:
    cpu: 500m
    memory: 512Mi
  port: 5555
  ingress: flower.mlworkbench.local

  features:
    - Real-time worker status
    - Task monitoring
    - Task history
    - Task retries
    - Worker management

# Flower for Federated Learning (framework)
flower_fl:
  deployment: Custom
  purpose: Federated learning coordination

  components:
    server:  # FL server
      replicas: 1
      resources:
        cpu: 2
        memory: 4Gi

    clients:  # FL workers
      replicas: 5-50 (dynamic)
      resources:
        cpu: 2-4
        memory: 8-16Gi
        gpu: 1 (optional, for image recognition)
```

### 3. MLflow - Experiment Tracking

**Purpose**: Track ML experiments and model lifecycle

```yaml
namespace: mlflow
components:
  - mlflow-server
  - postgresql (metadata)
  - MinIO (artifact storage)

features:
  - Experiment tracking
  - Model registry
  - Model versioning
  - A/B testing support

ingress: mlflow.mlworkbench.local
```

### 4. PostgreSQL - Metadata Database

**Purpose**: Metadata for Airflow, MLflow, applications

```yaml
namespace: databases
instances:
  airflow-db:
    version: 15
    storage: 20Gi
    replicas: 1

  mlflow-db:
    version: 15
    storage: 10Gi
    replicas: 1
```

### 5. Redis - Caching & Message Broker

**Purpose**: Caching and Celery message broker

```yaml
namespace: databases
mode: standalone  # or sentinel for HA
storage: 5Gi

use_cases:
  - Celery message broker (Airflow)
  - ML model cache
  - Session storage
  - Rate limiting cache
```

### 6. MinIO - Object Storage

**Purpose**: S3-compatible object storage

```yaml
namespace: minio
mode: standalone  # or distributed (4+ pods)
storage: 50Gi

use_cases:
  - MLflow artifacts
  - Airflow logs
  - Model checkpoints
  - Dataset storage (federated)
  - Backup storage

ingress: minio.mlworkbench.local
console: minio-console.mlworkbench.local
```

### 7. Monitoring - Prometheus + Grafana

**Purpose**: Metrics collection and visualization

```yaml
namespace: monitoring
components:
  prometheus:
    retention: 15 days
    storage: 20Gi

  grafana:
    storage: 5Gi
    dashboards:
      - Kubernetes cluster health
      - Federated learning metrics
      - GPU utilization
      - Model performance
      - Airflow metrics

  alertmanager:
    channels:
      - Email
      - Slack (optional)
```

### 8. Loki - Log Aggregation

**Purpose**: Centralized logging

```yaml
namespace: monitoring
retention: 7 days
storage: 20Gi

components:
  - Loki (log storage)
  - Promtail (log shipper)
  - Grafana (visualization)
```

---

## Layer 4: Federated Learning Applications

### 1. FL Coordinator Service

**Purpose**: Orchestrate federated learning rounds

```yaml
namespace: mlworkbench
replicas: 1

responsibilities:
  - Client selection strategy
  - Round management
  - Model aggregation (FedAvg, FedProx, etc.)
  - Model versioning
  - Communication with Airflow

resources:
  cpu: 2
  memory: 4Gi

storage:
  global_models: MinIO
  round_metadata: PostgreSQL
```

### 2. FL Worker Pool

**Purpose**: Execute local training on federated data

```yaml
namespace: mlworkbench
deployment: StatefulSet
replicas: 5-50 (dynamic scaling)

resources:
  cpu: 4
  memory: 16Gi
  gpu: 1 (NVIDIA T4/A10, optional)

storage:
  local_dataset: 20Gi per worker
  model_cache: 5Gi per worker
```

### 3. Image Recognition Pipeline

**Purpose**: Process and analyze images for FL

```yaml
namespace: mlworkbench
components:
  preprocessing:
    purpose: Image augmentation, normalization

  inference:
    purpose: Model serving for predictions

  postprocessing:
    purpose: Result aggregation, visualization
```

### 4. Model Registry

**Purpose**: Store and version ML models

```yaml
namespace: mlworkbench
backend: MLflow
features:
  - Model lineage tracking
  - A/B testing support
  - Promotion workflow (dev → staging → prod)
  - Model performance monitoring
```

### 5. API Gateway

**Purpose**: External API for FL clients

```yaml
namespace: mlworkbench
endpoints:
  POST /api/v1/fl/register_client
  GET  /api/v1/fl/model/latest
  POST /api/v1/fl/upload_update
  POST /api/v1/inference
  GET  /api/v1/models

authentication:
  - JWT tokens
  - API keys
  - mTLS for FL workers

ingress: api.mlworkbench.local (via Envoy Gateway)
```

---

## Deployment Guide

### Phase 1: Local virsh Setup (Week 1)

#### Step 1: Create VMs (5 minutes)

```bash
cd /var/home/ewt/mlworkbench/local-dev
./setup-talos-vms-disk.sh
```

**What it does:**
1. Downloads Talos v1.11.3 disk image (~170MB)
2. Creates 3 VMs with libvirt
3. Configures 50GB OS disk + 50GB data disk per VM
4. Starts all VMs

**Verify:**
```bash
sudo virsh list
# Should show 3 running VMs: talos-k8s-1, talos-k8s-2, talos-k8s-3
```

#### Step 2: Initialize Cluster (5-7 minutes)

```bash
./talos-cluster-init.sh
```

**What it does:**
1. Detects VM IPs via DHCP
2. Generates Talos configuration
3. Applies config to all nodes
4. Configures data disk mounting
5. Bootstraps etcd cluster
6. Retrieves kubeconfig
7. Verifies cluster health

**Output files:**
- `~/.talos-local/talosconfig` - Talos client config
- `~/.kube/talos-config` - Kubernetes kubeconfig

**Verify:**
```bash
export KUBECONFIG=~/.kube/talos-config
kubectl get nodes

# Expected:
# NAME            STATUS   ROLES           AGE   VERSION
# talos-k8s-1     Ready    control-plane   5m    v1.34.1
# talos-k8s-2     Ready    control-plane   5m    v1.34.1
# talos-k8s-3     Ready    control-plane   5m    v1.34.1
```

#### Step 3: Bootstrap ArgoCD (3 minutes)

```bash
cd ../gitops/bootstrap
./bootstrap-talos.sh
```

**What it does:**
1. Installs Gateway API CRDs
2. Creates argocd namespace
3. Deploys ArgoCD
4. Retrieves admin password
5. Saves password to `/tmp/argocd-admin-password.txt`

**Access ArgoCD:**
```bash
# Get password
cat /tmp/argocd-admin-password.txt

# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser: https://localhost:8080
# Username: admin
# Password: (from above)
```

#### Step 4: Deploy Foundational Services (2-3 minutes)

```bash
cd ../argocd-apps
kubectl apply -f root-app.yaml
```

**Deployed services:**
- ArgoCD (self-managed)
- External Secrets Operator
- cert-manager
- Envoy Gateway
- Tailscale
- MetalLB
- local-path-provisioner

**Monitor:**
```bash
kubectl get applications -n argocd -w

# Wait until all show: Synced + Healthy
```

#### Step 5: Deploy Platform Services (5-10 minutes)

Platform services will be defined in `root-app.yaml` or separate app:

```bash
kubectl apply -f platform-app.yaml
```

**Deployed services:**
- Airflow + Flower
- MLflow
- PostgreSQL (for Airflow, MLflow)
- Redis
- MinIO
- Prometheus + Grafana
- Loki

**Verify Airflow:**
```bash
kubectl get pods -n airflow

# Port forward to Airflow UI
kubectl port-forward -n airflow svc/airflow-webserver 8081:8080

# Open: http://localhost:8081
```

**Verify Flower:**
```bash
# Port forward to Flower UI
kubectl port-forward -n airflow svc/flower 5555:5555

# Open: http://localhost:5555
```

### Phase 2: Application Development (Week 2-4)

1. Develop FL coordinator service
2. Develop FL worker pool
3. Create Airflow DAGs for FL workflows
4. Implement image recognition pipeline
5. Set up model registry
6. Build API gateway

### Phase 3: Testing & Integration (Week 5-6)

1. End-to-end FL training test
2. Performance benchmarking
3. Fault tolerance testing (node failures)
4. Security testing
5. Documentation

### Phase 4: OVH Cloud Migration (Week 7-8)

See [OVH Cloud Migration Plan](#ovh-cloud-migration-plan) below.

---

## OVH Cloud Migration Plan

### Infrastructure on OVH

**Compute Instances:**
```yaml
control_plane:
  count: 3
  type: b2-15 (4 vCPU, 15GB RAM)
  os: Talos Linux v1.11.3
  disk: 100GB NVMe

worker_nodes:
  count: 3-10
  type: b2-30 (8 vCPU, 30GB RAM) or GPU instances
  os: Talos Linux v1.11.3
  disk: 200GB NVMe
  gpu: Optional (NVIDIA T4/V100 for image recognition)
```

**Networking:**
```yaml
private_network: vRack
  - Dedicated private network for cluster
  - No internet exposure for internal traffic

load_balancer: OVH Load Balancer
  - Public endpoint for API gateway
  - SSL termination

tailscale:
  - Secure connection between OVH and local dev
  - Remote access without VPN
```

**Storage:**
```yaml
block_storage: OVH Block Storage
  - Persistent volumes for databases
  - Model storage

object_storage: OVH Object Storage (S3-compatible)
  - Alternative to MinIO
  - Datasets and artifacts
```

### Migration Steps

1. **Provision OVH infrastructure** (Terraform)
   ```bash
   cd terraform/ovh
   terraform init
   terraform plan
   terraform apply
   ```

2. **Bootstrap Talos on OVH instances**
   - Same process as local
   - Different IPs and network config

3. **Connect via Tailscale**
   - Local cluster ↔ OVH cluster
   - Secure cross-cloud communication

4. **GitOps deployment**
   - Point ArgoCD to OVH cluster
   - Same Git repository, different overlays
   - Automated sync

5. **Data migration**
   - Models
   - Datasets
   - Historical metrics

6. **DNS and ingress**
   - Configure DNS for `mlworkbench.com`
   - SSL certificates via Let's Encrypt
   - Envoy Gateway for routing

---

## Directory Structure

```
/var/home/ewt/mlworkbench/
├── local-dev/                         # virsh/KVM setup
│   ├── setup-talos-vms-disk.sh       # Create VMs (verbatim from mlworkbench)
│   ├── talos-cluster-init.sh         # Initialize cluster (verbatim)
│   ├── talos-data-disk-patch.yaml    # Data disk config
│   ├── README.md                      # Local dev guide
│   └── TALOS_README.md                # Talos details
│
├── gitops/                            # GitOps configuration
│   ├── bootstrap/                     # Cluster bootstrap
│   │   ├── bootstrap-talos.sh        # Bootstrap script
│   │   ├── 1_SETUP_TALOS.md
│   │   ├── 2_DEPLOY_SECRETS.md
│   │   ├── 3_BOOTSTRAP_ARGOCD.md
│   │   └── 4_VERIFY_DEPLOYMENT.md
│   │
│   ├── argocd-apps/                   # ArgoCD Application definitions
│   │   ├── root-app.yaml             # App-of-apps
│   │   ├── foundation-app.yaml       # Foundational services
│   │   ├── platform-app.yaml         # ML platform services
│   │   ├── tailscale.yaml
│   │   ├── external-secrets.yaml
│   │   ├── envoy-gateway.yaml
│   │   ├── cert-manager.yaml
│   │   ├── airflow.yaml              # NEW: Airflow + Flower
│   │   ├── mlflow.yaml               # NEW: MLflow
│   │   ├── minio.yaml                # NEW: MinIO
│   │   └── monitoring.yaml
│   │
│   └── namespaces/                    # Kubernetes manifests by namespace
│       ├── tailscale/
│       │   ├── base/
│       │   └── overlays/default/
│       ├── external-secrets/
│       ├── envoy-gateway/
│       ├── cert-manager/
│       ├── airflow/                   # NEW: Airflow manifests
│       │   ├── base/
│       │   │   ├── deployment.yaml
│       │   │   ├── service.yaml
│       │   │   ├── configmap.yaml
│       │   │   └── pvc.yaml
│       │   └── overlays/
│       │       ├── local/
│       │       └── production/
│       ├── mlflow/                    # NEW: MLflow manifests
│       └── mlworkbench/                 # NEW: FL applications
│           ├── fl-coordinator/
│           ├── fl-worker/
│           ├── api-gateway/
│           └── model-registry/
│
├── terraform/                         # Infrastructure as Code
│   ├── virsh/                         # Local VMs (optional)
│   └── ovh/                           # OVH cloud resources
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── ovh-instances.tf
│
├── ansible/                           # Configuration management (optional)
│   ├── playbooks/
│   │   ├── bootstrap-vms.yml
│   │   └── gpu-setup.yml
│   └── inventory/
│       ├── local.ini
│       └── ovh.ini
│
├── scripts/                           # Utility scripts
│   ├── deploy-local.sh
│   ├── setup-secrets.sh
│   └── cleanup.sh
│
├── docs/                              # Documentation
│   ├── architecture.md
│   ├── deployment.md
│   ├── federated-learning.md
│   └── troubleshooting.md
│
├── INFRASTRUCTURE_OUTLINE.md          # This file
├── README.md                          # Project overview
└── .gitignore
```

---

## Key Differences from mlworkbench-com

### Removed (Not Needed)
- ❌ ImageRouter API integration
- ❌ Mollie/iDEAL payment service
- ❌ Frontend (React/Next.js)
- ❌ AI coloring service

### Added (For Federated Learning)
- ✅ **Apache Airflow** - ML workflow orchestration
- ✅ **Flower** - Celery monitoring + FL framework
- ✅ **MLflow** - Experiment tracking and model registry
- ✅ **FL Coordinator** - Federated learning orchestration
- ✅ **FL Worker Pool** - Distributed training workers
- ✅ **Image Recognition Pipeline** - CV model training
- ✅ **MinIO** - S3-compatible object storage

### Kept (Foundational)
- ✅ **Talos Linux** - Same immutable Kubernetes OS
- ✅ **ArgoCD** - Same GitOps pattern
- ✅ **External Secrets** - Same secrets management
- ✅ **Envoy Gateway** - Same modern ingress
- ✅ **Tailscale** - Same VPN mesh
- ✅ **cert-manager** - Same TLS automation
- ✅ **Prometheus + Grafana** - Same monitoring
- ✅ **Loki** - Same log aggregation
- ✅ **PostgreSQL** - Database (different use case)
- ✅ **Redis** - Cache/broker (different use case)

---

## Next Steps

1. ✅ **Review this outline** - Ensure alignment with requirements
2. ⏭️ **Copy virsh scripts** - Verbatim from mlworkbench
3. ⏭️ **Create ArgoCD apps** - Define Airflow, Flower, MLflow
4. ⏭️ **Create Kubernetes manifests** - For new services
5. ⏭️ **Set up local cluster** - Run through deployment
6. ⏭️ **Develop FL applications** - Coordinator, workers, API
7. ⏭️ **Test end-to-end** - Full FL training workflow
8. ⏭️ **Plan OVH migration** - Terraform configs

---

## Useful Commands

### Talos Management
```bash
# Set aliases
export TALOSCONFIG=~/.talos-local/talosconfig
export KUBECONFIG=~/.kube/talos-config
alias talos='talosctl --talosconfig $TALOSCONFIG'

# Health check
talos health

# Dashboard
talos dashboard

# Logs
talos logs kubelet
talos logs etcd
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
```

### ArgoCD Management
```bash
# List apps
kubectl get applications -n argocd

# Sync app
argocd app sync <app-name>

# Via kubectl
kubectl patch application <app-name> -n argocd --type merge --patch '{"operation":{"sync":{}}}'
```

### Airflow Management
```bash
# Access Airflow UI
kubectl port-forward -n airflow svc/airflow-webserver 8081:8080

# Trigger DAG
airflow dags trigger federated_learning_round

# View logs
kubectl logs -n airflow -l component=scheduler
```

### Flower Management
```bash
# Access Flower UI
kubectl port-forward -n airflow svc/flower 5555:5555

# Check worker status
curl http://localhost:5555/api/workers
```

---

## Resources

- **Talos Documentation**: https://www.talos.dev/
- **ArgoCD Documentation**: https://argo-cd.readthedocs.io/
- **Apache Airflow**: https://airflow.apache.org/docs/
- **Flower (FL)**: https://flower.ai/docs/
- **MLflow**: https://mlflow.org/docs/latest/index.html
- **Envoy Gateway**: https://gateway.envoyproxy.io/

---

**Ready to deploy?**

```bash
cd /var/home/ewt/mlworkbench/local-dev
./setup-talos-vms-disk.sh
```
