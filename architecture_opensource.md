# Architecture A: Fully Open Source Solution
## Collaborative Federated Learning Platform for Agricultural Robotics

---

## 1. Architecture Overview

### Design Principles
- **Complete data sovereignty**: Each organization hosts their own data
- **No vendor lock-in**: All components are open source
- **On-premise first**: Can run entirely on organization's infrastructure
- **Cost-effective**: No licensing fees, only infrastructure costs
- **Transparent**: Full visibility into all operations

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Federated Learning Network                    │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
   ┌────▼─────┐         ┌────▼─────┐         ┌────▼─────┐
   │ Company A │         │ Company B │         │ Company C │
   │   Node    │         │   Node    │         │   Node    │
   └────┬─────┘         └────┬─────┘         └────┬─────┘
        │                     │                     │
   ┌────▼──────────────┐┌────▼──────────────┐┌────▼──────────────┐
   │ Local Components  ││ Local Components  ││ Local Components  │
   │                   ││                   ││                   │
   │ • Data Storage    ││ • Data Storage    ││ • Data Storage    │
   │ • Image Pipeline  ││ • Image Pipeline  ││ • Image Pipeline  │
   │ • Training Engine ││ • Training Engine ││ • Training Engine │
   │ • Model Registry  ││ • Model Registry  ││ • Model Registry  │
   └───────────────────┘└───────────────────┘└───────────────────┘
```

---

## 2. Technology Stack

### 2.1 Data Storage Layer

**Object Storage: MinIO**
- S3-compatible API
- Distributed deployment
- Versioning support
- Encryption at rest

**Metadata Database: PostgreSQL**
- Image metadata
- Annotation data
- User permissions
- Audit logs

**Data Lake: Apache Iceberg**
- ACID transactions
- Time travel
- Schema evolution
- Partition pruning

### 2.2 Image Processing Pipeline

**Image Transformation: PyTorch + Albumentations**
```python
# Core transformation pipeline components
- Color normalization (histogram matching)
- Perspective correction (homography)
- Domain adaptation (CycleGAN)
- Quality assessment
- Format standardization
```

**Processing Framework: Apache Airflow**
- Orchestrate ETL pipelines
- Schedule batch processing
- Monitor data quality
- Handle failures

**Image Processing: OpenCV + Pillow**
- Geometric transformations
- Color space conversions
- Quality metrics (SSIM, PSNR)
- Metadata extraction (EXIF)

### 2.3 Annotation Platform

**Tool: Label Studio (Open Source)**
```yaml
Features:
  - Web-based interface
  - Semantic segmentation
  - Bounding boxes
  - Classification
  - Multi-user support
  - API for automation
```

**Auto-Annotation: Grounded SAM + YOLO**
- Pre-annotation with YOLO for detection
- Segment Anything for refinement
- Human verification workflow
- Active learning selection

### 2.4 Federated Learning Framework

**Core Framework: Flower (flwr.dev)**
```
Architecture:
┌──────────────────┐
│  Flower Server   │  ← Aggregation coordinator
└────────┬─────────┘
         │
    ┌────┴────┬────────┬────────┐
    │         │        │        │
┌───▼──┐  ┌──▼──┐  ┌──▼──┐  ┌──▼──┐
│Client│  │Client│  │Client│  │Client│ ← Local training
│  1   │  │  2  │  │  3  │  │  4  │
└──────┘  └─────┘  └─────┘  └─────┘
```

**Key Flower Features:**
- Framework-agnostic (PyTorch, TensorFlow)
- Flexible aggregation strategies
- Secure aggregation support
- Simulation mode for testing
- Differential privacy integration

**Alternative: PySyft**
- If stronger privacy guarantees needed
- Supports encrypted computation
- More complex setup

### 2.5 Model Training & Serving

**Training Framework: PyTorch**
```python
# Model architecture options
- ResNet / EfficientNet for classification
- DeepLabV3+ / U-Net for segmentation
- YOLO / Faster R-CNN for detection
- Vision Transformers (ViT) for robust features
```

**Model Registry: MLflow**
- Model versioning
- Experiment tracking
- Model lineage
- Metadata storage
- Model comparison

**Model Serving: TorchServe**
- REST/gRPC APIs
- Batch inference
- Model versioning
- Metrics collection
- A/B testing support

### 2.6 Edge Deployment

**Optimization: ONNX + TensorRT**
```
Training (PyTorch) → ONNX → TensorRT → Optimized Engine
                                            │
                                            ▼
                                    ┌───────────────┐
                                    │  Robot Edge   │
                                    │  (Jetson)     │
                                    └───────────────┘
```

**Edge Runtime: ONNX Runtime**
- Cross-platform
- Hardware acceleration
- Low latency
- Small footprint

**Target Hardware:**
- NVIDIA Jetson Orin/Xavier
- Intel NUC + Neural Compute Stick
- Raspberry Pi 4/5 + Coral TPU

### 2.7 MLOps & Monitoring

**Experiment Tracking: Weights & Biases (Community Edition)**
- Free for open source projects
- Comprehensive logging
- Visualization
- Team collaboration

**Alternative: MLflow + Custom UI**
- Fully self-hosted
- Integrated with model registry
- Python API

**Data Versioning: DVC (Data Version Control)**
```bash
# Track datasets
dvc add data/images/batch_001/
git add data/images/batch_001.dvc
git commit -m "Add new image batch"
```

**Model Monitoring: Evidently AI**
- Data drift detection
- Model performance monitoring
- Open source
- Integrated reporting

### 2.8 API & Integration Layer

**API Gateway: Kong (Open Source)**
- Authentication
- Rate limiting
- API analytics
- Plugin ecosystem

**API Framework: FastAPI**
```python
# RESTful API for platform
- Image upload
- Annotation retrieval
- Model inference
- Federated learning coordination
```

**Message Queue: Apache Kafka**
- Event streaming
- Decouple components
- Reliable delivery
- High throughput

### 2.9 Security & Privacy

**Authentication: Keycloak**
- SSO (Single Sign-On)
- OAuth 2.0 / OpenID Connect
- User federation
- Role-based access control

**Privacy: OpenMined PySyft + Differential Privacy**
```python
# Add differential privacy to training
import opacus

privacy_engine = opacus.PrivacyEngine()
model, optimizer, dataloader = privacy_engine.make_private(
    module=model,
    optimizer=optimizer,
    data_loader=dataloader,
    noise_multiplier=1.1,
    max_grad_norm=1.0,
)
```

**Data Governance: Apache Atlas**
- Metadata management
- Data lineage
- Classification
- Audit trail

### 2.10 Infrastructure

**Container Orchestration: Kubernetes**
- Managed with k3s (lightweight) or microk8s
- Helm charts for deployment
- Horizontal scaling
- Service mesh (Istio optional)

**Infrastructure as Code: Terraform + Ansible**
- Reproducible deployments
- Version controlled infrastructure
- Multi-environment support

**Monitoring: Prometheus + Grafana**
- Metrics collection
- Alerting
- Visualization dashboards
- Long-term storage (Thanos)

**Logging: ELK Stack (Elasticsearch, Logstash, Kibana)**
- Centralized logging
- Log analysis
- Search capabilities
- Retention policies

---

## 3. Detailed Component Design

### 3.1 Image Transformation Module

```python
class ImageTransformationPipeline:
    """
    Standardizes images from different sources
    """
    def __init__(self):
        self.color_normalizer = HistogramMatcher()
        self.perspective_corrector = HomographyEstimator()
        self.domain_adapter = CycleGAN()
        self.quality_assessor = ImageQualityMetrics()

    def transform(self, image, metadata):
        # 1. Correct perspective
        corrected = self.perspective_corrector.apply(image)

        # 2. Normalize colors
        normalized = self.color_normalizer.match_reference(corrected)

        # 3. Domain adaptation
        adapted = self.domain_adapter.transform(normalized)

        # 4. Quality check
        quality_score = self.quality_assessor.evaluate(adapted)

        return adapted, quality_score
```

**Transformation Types:**
1. **Geometric**: Rectification, rotation, scaling
2. **Photometric**: Brightness, contrast, color temperature
3. **Domain Adaptation**: Style transfer to canonical representation
4. **Quality**: Blur detection, noise reduction

### 3.2 Federated Learning Workflow

```python
# Server-side (Flower)
import flwr as fl

def weighted_average(metrics):
    """Aggregate model updates"""
    accuracies = [num_examples * m["accuracy"] for num_examples, m in metrics]
    examples = [num_examples for num_examples, _ in metrics]
    return {"accuracy": sum(accuracies) / sum(examples)}

strategy = fl.server.strategy.FedAvg(
    min_fit_clients=3,
    min_available_clients=3,
    evaluate_fn=evaluate_global_model,
    on_fit_config_fn=fit_config,
)

fl.server.start_server(
    server_address="0.0.0.0:8080",
    config=fl.server.ServerConfig(num_rounds=100),
    strategy=strategy,
)

# Client-side
class AgroClient(fl.client.NumPyClient):
    def __init__(self, model, trainloader, testloader):
        self.model = model
        self.trainloader = trainloader
        self.testloader = testloader

    def get_parameters(self, config):
        return [val.cpu().numpy() for _, val in self.model.state_dict().items()]

    def fit(self, parameters, config):
        set_parameters(self.model, parameters)
        train(self.model, self.trainloader, epochs=5)
        return self.get_parameters({}), len(self.trainloader), {}

    def evaluate(self, parameters, config):
        set_parameters(self.model, parameters)
        loss, accuracy = test(self.model, self.testloader)
        return float(loss), len(self.testloader), {"accuracy": float(accuracy)}
```

### 3.3 Data Governance Model

```yaml
# Data Sharing Agreement Schema
data_sharing_agreement:
  version: "1.0"
  parties:
    - organization_id: "company_a"
      role: "data_provider"
      permissions: ["read_own", "write_own", "train_federated"]
    - organization_id: "company_b"
      role: "data_provider"
      permissions: ["read_own", "write_own", "train_federated"]

  data_rights:
    ownership: "original_provider"
    usage_rights:
      - "model_training"
      - "model_validation"
    restrictions:
      - "no_raw_data_export"
      - "no_third_party_sharing"

  model_rights:
    trained_model_ownership: "shared"
    distribution: "all_participants"
    commercial_use: true
    attribution_required: true

  audit:
    logging_required: true
    retention_period_days: 365
    audit_access: ["all_parties", "governance_board"]
```

---

## 4. Deployment Architecture

### 4.1 Single Organization Node

```
┌─────────────────────────────────────────────────────┐
│              Organization Node (On-Premise)          │
├─────────────────────────────────────────────────────┤
│                                                      │
│  ┌──────────────┐  ┌──────────────┐                │
│  │   Ingress    │  │  API Gateway │                │
│  │   (Nginx)    │  │   (Kong)     │                │
│  └──────┬───────┘  └──────┬───────┘                │
│         │                  │                         │
│  ┌──────▼──────────────────▼───────┐                │
│  │     Kubernetes Cluster          │                │
│  │  ┌────────────────────────────┐ │                │
│  │  │  Application Pods          │ │                │
│  │  │  • FastAPI (REST API)      │ │                │
│  │  │  • Flower Client           │ │                │
│  │  │  • Airflow Workers         │ │                │
│  │  │  • Label Studio            │ │                │
│  │  │  • MLflow Server           │ │                │
│  │  │  • TorchServe              │ │                │
│  │  └────────────────────────────┘ │                │
│  │  ┌────────────────────────────┐ │                │
│  │  │  GPU Pods (Training)       │ │                │
│  │  │  • PyTorch Training        │ │                │
│  │  │  • Image Processing        │ │                │
│  │  └────────────────────────────┘ │                │
│  └────────────────┬────────────────┘                │
│                   │                                  │
│  ┌────────────────▼────────────────┐                │
│  │    Storage Layer                │                │
│  │  • MinIO (Object Storage)       │                │
│  │  • PostgreSQL (Metadata)        │                │
│  │  • Iceberg Tables (Data Lake)   │                │
│  └─────────────────────────────────┘                │
│                                                      │
│  ┌─────────────────────────────────┐                │
│  │  Monitoring & Logging            │                │
│  │  • Prometheus                    │                │
│  │  • Grafana                       │                │
│  │  • Elasticsearch                 │                │
│  └─────────────────────────────────┘                │
└─────────────────────────────────────────────────────┘
```

### 4.2 Network Topology

```
        Internet
           │
           ▼
┌──────────────────┐
│ Flower Server    │ ← Coordination Server (Can be hosted by consortium)
│ (Aggregation)    │
└────────┬─────────┘
         │
    ┌────┴─────────┬──────────┬──────────┐
    │              │          │          │
    ▼              ▼          ▼          ▼
┌────────┐    ┌────────┐ ┌────────┐ ┌────────┐
│ Org A  │    │ Org B  │ │ Org C  │ │ Org D  │
│ Node   │    │ Node   │ │ Node   │ │ Node   │
└────┬───┘    └────┬───┘ └────┬───┘ └────┬───┘
     │             │          │          │
┌────▼─────┐  ┌───▼──────┐ ┌─▼────────┐ ┌▼────────┐
│  Robots  │  │  Robots  │ │  Robots  │ │  Robots │
│ (Edge)   │  │ (Edge)   │ │ (Edge)   │ │ (Edge)  │
└──────────┘  └──────────┘ └──────────┘ └─────────┘
```

---

## 5. Implementation Phases

### Phase 1: Core Infrastructure (4 weeks)
**Deliverables:**
- Kubernetes cluster setup
- MinIO storage deployment
- PostgreSQL database
- Basic API with FastAPI
- Authentication (Keycloak)

**Tech Stack Setup:**
```bash
# Install k3s (lightweight Kubernetes)
curl -sfL https://get.k3s.io | sh -

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Deploy MinIO
helm repo add minio https://charts.min.io/
helm install minio minio/minio --set persistence.size=500Gi

# Deploy PostgreSQL
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install postgres bitnami/postgresql

# Deploy Keycloak
helm repo add codecentric https://codecentric.github.io/helm-charts
helm install keycloak codecentric/keycloak
```

### Phase 2: Image Pipeline (3 weeks)
**Deliverables:**
- Image upload/download API
- Transformation pipeline
- Quality assessment
- Metadata extraction
- Airflow DAGs

**Components:**
```python
# Example Airflow DAG
from airflow import DAG
from airflow.operators.python import PythonOperator

dag = DAG('image_processing', schedule_interval='@hourly')

upload_task = PythonOperator(
    task_id='detect_new_images',
    python_callable=scan_for_new_images,
    dag=dag
)

transform_task = PythonOperator(
    task_id='transform_images',
    python_callable=run_transformation_pipeline,
    dag=dag
)

quality_task = PythonOperator(
    task_id='assess_quality',
    python_callable=assess_image_quality,
    dag=dag
)

upload_task >> transform_task >> quality_task
```

### Phase 3: Annotation System (2 weeks)
**Deliverables:**
- Label Studio deployment
- Auto-annotation with YOLO
- SAM integration
- Annotation export API

### Phase 4: Federated Learning (4 weeks)
**Deliverables:**
- Flower server deployment
- Client libraries
- Training orchestration
- Model aggregation
- Privacy mechanisms

### Phase 5: MLOps & Deployment (3 weeks)
**Deliverables:**
- MLflow registry
- Model versioning
- TorchServe deployment
- ONNX export pipeline
- Edge deployment scripts

### Phase 6: Monitoring & Governance (2 weeks)
**Deliverables:**
- Prometheus/Grafana dashboards
- ELK stack for logs
- Data governance framework
- Access control policies
- Audit logging

---

## 6. Cost Estimation

### Hardware Requirements (Per Organization Node)

**Minimum Setup:**
- CPU Server: AMD EPYC 7402P (24 cores) or Intel Xeon Silver 4314
- RAM: 128 GB DDR4
- Storage: 10 TB NVMe SSD + 50 TB HDD
- GPU: 2x NVIDIA RTX 4090 or A4000
- Network: 10 Gbps connection
- **Estimated Cost: €15,000 - €25,000**

**Recommended Setup:**
- CPU Server: AMD EPYC 7543 (32 cores) or Intel Xeon Gold 6338
- RAM: 256 GB DDR4
- Storage: 20 TB NVMe SSD + 100 TB HDD
- GPU: 2x NVIDIA A6000 or A100
- Network: 25 Gbps connection
- **Estimated Cost: €35,000 - €55,000**

### Software Costs
- **All components: €0** (Open Source)
- Optional: Weights & Biases Team Plan: €50/month/user
- Optional: Support contracts for critical components

### Operational Costs (Annual)
- Electricity: ~€3,000 - €5,000
- Internet: €1,000 - €2,000
- Maintenance: €2,000 - €5,000
- **Total Annual: €6,000 - €12,000**

### Personnel (Development)
- Initial setup: 1-2 ML Engineers, 1 DevOps Engineer, 3-6 months
- Maintenance: 0.5 FTE ongoing

---

## 7. Advantages of Open Source Solution

### Strengths:
1. **Complete Control**: Full ownership of code and data
2. **Customization**: Can modify any component
3. **Cost**: No licensing fees
4. **Privacy**: Data never leaves premises
5. **Transparency**: Auditability of all operations
6. **Community**: Large open source communities

### Challenges:
1. **Expertise Required**: Need skilled team to operate
2. **Setup Complexity**: Longer time to production
3. **Maintenance**: Ongoing updates and patches
4. **Scaling**: Manual scaling configuration
5. **Support**: Community support vs. SLA-backed

---

## 8. Risk Mitigation

### Technical Risks:
- **GPU Availability**: Plan for CPU fallback, cloud GPU burst
- **Network Failures**: Implement retry logic, offline training
- **Data Corruption**: Regular backups, checksums, versioning

### Operational Risks:
- **Skills Gap**: Training programs, documentation
- **Single Points of Failure**: Redundancy, high availability
- **Security**: Regular audits, penetration testing

---

## 9. Success Criteria

### Technical Metrics:
- Image transformation quality: SSIM > 0.85
- Federated learning convergence: Within 10% of centralized
- Edge inference: < 100ms latency
- System uptime: > 99%

### Business Metrics:
- Cost per training run: < €100
- Onboarding time: < 2 weeks
- User satisfaction: > 4/5
- Data contribution: > 80% of participants

---

## 10. Next Steps

1. **Validate with stakeholders**: Present architecture for feedback
2. **Build PoC**: Single-node deployment with sample data
3. **Test federation**: Multi-organization pilot
4. **Iterate**: Refine based on real-world usage
5. **Scale**: Production rollout across consortium

---

*This architecture provides a robust, cost-effective foundation for collaborative AI development while maintaining complete data sovereignty.*
