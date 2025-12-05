# MLWorkbench - Federated Learning Platform

Complete infrastructure for federated learning and image recognition on Kubernetes, powered by Talos Linux.

---

## 🚀 Quick Start

Deploy a complete federated learning platform in 15 minutes:

```bash
# 1. Create Talos VMs
cd local-dev && ./setup-talos-vms-disk.sh

# 2. Initialize cluster
./talos-cluster-init.sh

# 3. Bootstrap ArgoCD
cd ../gitops/bootstrap && ./bootstrap-talos.sh

# 4. Deploy all services
cd ../argocd-apps
sed -i 's|YOUR_USERNAME|your-github-username|g' *.yaml
kubectl apply -f root-app.yaml
```

**📖 See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for detailed instructions.**

---

## 📁 Repository Structure

```
mlworkbench/
├── local-dev/                      # Talos Linux VM setup (virsh/KVM)
│   ├── setup-talos-vms-disk.sh   # Create 3 Talos VMs
│   ├── talos-cluster-init.sh     # Initialize Kubernetes cluster
│   ├── talos-data-disk-patch.yaml
│   ├── README.md
│   └── TALOS_README.md
│
├── gitops/                         # GitOps configuration
│   ├── bootstrap/                  # Cluster bootstrap
│   │   └── bootstrap-talos.sh    # Install ArgoCD
│   │
│   ├── argocd-apps/                # ArgoCD Application definitions
│   │   ├── root-app.yaml         # App-of-apps (deploy this!)
│   │   ├── argocd.yaml
│   │   ├── external-secrets.yaml
│   │   ├── cert-manager.yaml
│   │   ├── envoy-gateway.yaml
│   │   ├── tailscale.yaml
│   │   ├── metallb.yaml
│   │   ├── local-path-provisioner.yaml
│   │   ├── airflow.yaml          # Apache Airflow
│   │   ├── mlflow.yaml           # MLflow
│   │   ├── minio.yaml            # S3-compatible storage
│   │   ├── postgresql.yaml       # Database
│   │   ├── redis.yaml            # Cache/broker
│   │   ├── monitoring.yaml       # Prometheus + Grafana
│   │   └── loki.yaml             # Log aggregation
│   │
│   └── namespaces/                 # Kubernetes manifests (Kustomize)
│       ├── argocd/
│       ├── external-secrets/
│       ├── cert-manager/
│       ├── envoy-gateway/
│       ├── tailscale/
│       ├── metallb/
│       ├── local-path-provisioner/
│       ├── airflow/
│       ├── mlflow/
│       ├── minio/
│       ├── postgresql/
│       ├── redis/
│       ├── monitoring/
│       ├── loki/
│       └── mlworkbench/          # Your FL applications
│
├── infrastructure/                 # [REFERENCE ONLY - Can be deleted]
│   └── (reference infrastructure files)
│
├── INFRASTRUCTURE_OUTLINE.md       # Complete architecture guide
├── DEPLOYMENT_GUIDE.md             # Step-by-step deployment
├── SETUP_SUMMARY.md                # What's done, what's next
└── README.md                       # This file
```

---

## 🎯 What's Included

### Layer 0: Virtualization (virsh/KVM)
- ✅ 3 Talos Linux VMs (control-plane nodes)
- ✅ 2 vCPUs, 8GB RAM per node
- ✅ 50GB OS disk + 50GB data disk per node
- ✅ libvirt default network (192.168.122.0/24)

### Layer 1: Kubernetes (Talos v1.11.3)
- ✅ Talos Linux (immutable, API-driven, secure)
- ✅ Kubernetes v1.34.1
- ✅ 3-node etcd cluster
- ✅ All nodes schedulable (no dedicated workers)

### Layer 2: Foundational Services
- ✅ **ArgoCD** - GitOps continuous delivery
- ✅ **Tailscale** - VPN mesh network
- ✅ **External Secrets Operator** - Secrets management
- ✅ **Envoy Gateway** - Modern API gateway (Gateway API)
- ✅ **cert-manager** - TLS certificate automation
- ✅ **MetalLB** - Load balancer for bare metal
- ✅ **local-path-provisioner** - Dynamic storage provisioning

### Layer 3: ML Platform Services
- ✅ **Apache Airflow** - Workflow orchestration (KubernetesExecutor)
- ✅ **MLflow** - Experiment tracking and model registry
- ✅ **MinIO** - S3-compatible object storage
- ✅ **PostgreSQL** - Relational database
- ✅ **Redis** - Caching and message broker
- ✅ **Prometheus + Grafana** - Monitoring and visualization
- ✅ **Loki** - Log aggregation

### Layer 4: Federated Learning Applications (TODO)
- ⏭️ FL Coordinator - Orchestrate FL rounds
- ⏭️ FL Worker Pool - Distributed training
- ⏭️ Image Recognition Pipeline - CV model training
- ⏭️ API Gateway - External API for clients
- ⏭️ Model Registry - Model versioning and deployment

---

## 📊 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Your Host (Fedora 43)                                          │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  libvirt/KVM                                            │    │
│  │                                                          │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │    │
│  │  │ talos-k8s-1  │  │ talos-k8s-2  │  │ talos-k8s-3  │ │    │
│  │  │ Control Plane│  │ Control Plane│  │ Control Plane│ │    │
│  │  │ + etcd       │  │ + etcd       │  │ + etcd       │ │    │
│  │  │ OS: 50GB     │  │ OS: 50GB     │  │ OS: 50GB     │ │    │
│  │  │ Data: 50GB   │  │ Data: 50GB   │  │ Data: 50GB   │ │    │
│  │  │ 8GB RAM      │  │ 8GB RAM      │  │ 8GB RAM      │ │    │
│  │  │ 2 vCPU       │  │ 2 vCPU       │  │ 2 vCPU       │ │    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘ │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Kubernetes Services (ArgoCD-managed)                   │    │
│  │                                                          │    │
│  │  Foundational: ArgoCD, Envoy Gateway, cert-manager     │    │
│  │  Platform: Airflow, MLflow, MinIO, PostgreSQL          │    │
│  │  Monitoring: Prometheus, Grafana, Loki                 │    │
│  │  Apps: FL Coordinator, FL Workers, API Gateway         │    │
│  └────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

---

## 🛠️ Key Technologies

| Category | Technology | Purpose |
|----------|-----------|---------|
| **OS** | Talos Linux v1.11.3 | Immutable Kubernetes OS |
| **Orchestration** | Kubernetes v1.34.1 | Container orchestration |
| **GitOps** | ArgoCD | Declarative deployment |
| **Ingress** | Envoy Gateway | Modern API gateway |
| **Storage** | local-path-provisioner | Dynamic PV provisioning |
| **Networking** | MetalLB | Load balancer |
| **Secrets** | External Secrets | Secrets management |
| **Certificates** | cert-manager | TLS automation |
| **Workflows** | Apache Airflow | ML pipeline orchestration |
| **ML Tracking** | MLflow | Experiment tracking |
| **Object Storage** | MinIO | S3-compatible storage |
| **Database** | PostgreSQL 15 | Relational database |
| **Cache** | Redis 7 | Caching and message broker |
| **Monitoring** | Prometheus + Grafana | Metrics and dashboards |
| **Logging** | Loki | Log aggregation |
| **VPN** | Tailscale | Mesh network |

---

## 📖 Documentation

- **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** - Complete step-by-step deployment guide
- **[INFRASTRUCTURE_OUTLINE.md](INFRASTRUCTURE_OUTLINE.md)** - Detailed architecture and design
- **[SETUP_SUMMARY.md](SETUP_SUMMARY.md)** - What's done and what's next
- **[local-dev/README.md](local-dev/README.md)** - Local development guide
- **[local-dev/TALOS_README.md](local-dev/TALOS_README.md)** - Talos Linux details

---

## 🚦 Getting Started

### Prerequisites

- Fedora 43 (or any Linux with KVM support)
- 8+ CPU cores, 32GB+ RAM, 350GB+ disk
- libvirt, talosctl, kubectl, yq installed

### Deploy Now

```bash
# 1. Clone repository
git clone https://github.com/YOUR_USERNAME/mlworkbench.git
cd mlworkbench

# 2. Create VMs and cluster
cd local-dev
./setup-talos-vms-disk.sh
./talos-cluster-init.sh

# 3. Bootstrap ArgoCD
cd ../gitops/bootstrap
./bootstrap-talos.sh

# 4. Update repository URLs
cd ../argocd-apps
find . -name '*.yaml' -exec sed -i 's|YOUR_USERNAME|YOUR_GITHUB_USERNAME|g' {} +

# 5. Deploy all services
kubectl apply -f root-app.yaml

# 6. Watch deployment
kubectl get applications -n argocd -w
```

**Time**: ~15 minutes total

### Access Services

```bash
# ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080 (admin / see /tmp/argocd-admin-password.txt)

# Airflow UI
kubectl port-forward svc/airflow-webserver -n airflow 8081:8080
# http://localhost:8081 (admin / admin)

# Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
# http://localhost:3000 (admin / admin)

# MLflow
kubectl port-forward svc/mlflow -n mlflow 5000:5000
# http://localhost:5000

# MinIO Console
kubectl port-forward svc/minio-console -n minio 9001:9001
# http://localhost:9001 (minio / minio123)
```

---

## 🔄 GitOps Workflow

All infrastructure is managed via GitOps:

1. **Make changes** to YAML files in `gitops/`
2. **Commit and push** to Git
3. **ArgoCD automatically syncs** changes to cluster
4. **Verify** in ArgoCD UI or kubectl

**Example: Add a new service**
```bash
# 1. Create ArgoCD Application
cat > gitops/argocd-apps/my-service.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-service
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/YOUR_USERNAME/mlworkbench.git
    targetRevision: main
    path: gitops/namespaces/my-service/overlays/local
  destination:
    server: https://kubernetes.default.svc
    namespace: my-namespace
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# 2. Commit and push
git add gitops/argocd-apps/my-service.yaml
git commit -m "Add my-service application"
git push

# 3. ArgoCD will automatically deploy it!
```

---

## 🧹 Cleanup

### Delete all services
```bash
kubectl delete -f gitops/argocd-apps/root-app.yaml
```

### Destroy VMs
```bash
cd local-dev
for i in {1..3}; do
  sudo virsh destroy talos-k8s-$i 2>/dev/null || true
  sudo virsh undefine talos-k8s-$i --remove-all-storage
done
rm -rf ~/.talos-local ~/.kube/talos-config
```

### Remove reference repository (after copying)
```bash
rm -rf infrastructure/
```

---

## 🎯 Next Steps

1. **Deploy FL Applications**
   - Create FL Coordinator service
   - Create FL Worker Pool
   - Implement image recognition pipeline

2. **Create Airflow DAGs**
   - Federated learning workflows
   - Data preprocessing pipelines
   - Model evaluation jobs

3. **Configure Monitoring**
   - Custom Grafana dashboards
   - Prometheus alerting rules
   - FL-specific metrics

4. **Plan OVH Migration**
   - Follow guide in `INFRASTRUCTURE_OUTLINE.md`
   - Provision OVH instances
   - Deploy via same GitOps approach

---

## 🤝 Contributing

This infrastructure is based on the proven [idea2coloring-com/infrastructure](https://github.com/idea2coloring-com/infrastructure) setup, adapted for federated learning workloads.

---

## 📝 License

[Add your license here]

---

## 🙏 Acknowledgments

- Infrastructure patterns from **idea2coloring-com**
- **Talos Linux** for the secure, immutable Kubernetes OS
- **ArgoCD** for GitOps excellence
- The Kubernetes community

---

## 📧 Support

For issues or questions:
1. Check [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) troubleshooting section
2. Review logs: `kubectl logs <pod> -n <namespace>`
3. Check ArgoCD UI for sync errors

---

**Built with ❤️ for Federated Learning**
