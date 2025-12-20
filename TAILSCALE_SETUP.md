# Tailscale Kubernetes Operator Setup Guide

This guide walks you through setting up Tailscale Operator to expose your ML Workbench services via Tailscale.

## Prerequisites

1. **Tailscale Account**: Sign up at https://tailscale.com
2. **Tailnet Access**: Admin access to your tailnet
3. **Cluster Running**: ML Workbench cluster deployed with ArgoCD

## Step 1: Configure Tailnet ACLs

Add the required tags to your tailnet ACL policy at https://login.tailscale.com/admin/acls/file

```json
{
  "tagOwners": {
    "tag:k8s-operator": [],
    "tag:k8s": ["tag:k8s-operator"]
  },

  "acls": [
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["tag:k8s:*"]
    }
  ]
}
```

**Explanation**:
- `tag:k8s-operator` - Tags the operator itself
- `tag:k8s` - Tags services exposed from Kubernetes
- The ACL allows all tailnet members to access k8s-tagged services

## Step 2: Create OAuth Client

1. Go to https://login.tailscale.com/admin/settings/oauth
2. Click **Generate OAuth Client**
3. Select the following scopes:
   - **Devices**: Write
   - **Auth Keys**: Write
   - **Services**: Write
4. Save the **Client ID** and **Client Secret**

## Step 3: Create Sealed Secret

Using the OAuth credentials from Step 2:

```bash
# Make sure sealed-secrets controller is running
kubectl wait --for=condition=available --timeout=120s \
  deployment/sealed-secrets-controller -n sealed-secrets

# Create the sealed secret (replace YOUR_CLIENT_ID and YOUR_CLIENT_SECRET)
kubectl create secret generic operator-oauth \
  --from-literal=client_id=YOUR_CLIENT_ID \
  --from-literal=client_secret=YOUR_CLIENT_SECRET \
  --namespace=tailscale \
  --dry-run=client -o yaml | \
kubeseal --format yaml --controller-namespace sealed-secrets \
  > gitops/namespaces/tailscale/base/operator-oauth-sealed.yaml
```

## Step 4: Commit and Deploy

```bash
# Add the sealed secret to Git
git add gitops/namespaces/tailscale/base/operator-oauth-sealed.yaml

# Commit all Tailscale changes
git add gitops/
git commit -m "Configure Tailscale operator with ingress for all services"
git push

# ArgoCD will automatically sync the changes
# Monitor the deployment:
kubectl get applications -n argocd
kubectl get pods -n tailscale -w
```

## Step 5: Verify Deployment

```bash
# Check Tailscale operator is running
kubectl get pods -n tailscale
kubectl logs -n tailscale -l app.kubernetes.io/name=tailscale-operator

# Check that Tailscale devices were created
# You should see new devices in your tailnet at:
# https://login.tailscale.com/admin/machines
```

## Step 6: Access Your Services

Once the operator is running and services are exposed, you can access them via Tailscale:

### Service URLs

All services will be accessible at `https://<hostname>.<your-tailnet>.ts.net`:

| Service | Tailscale URL | Description |
|---------|--------------|-------------|
| **ArgoCD** | `https://argocd.<tailnet>.ts.net` | GitOps dashboard |
| **Airflow** | `https://airflow.<tailnet>.ts.net` | Workflow orchestration |
| **Grafana** | `https://grafana.<tailnet>.ts.net` | Metrics & dashboards |
| **Prometheus** | `https://prometheus.<tailnet>.ts.net` | Metrics database |
| **MLflow** | `https://mlflow.<tailnet>.ts.net` | ML experiment tracking |
| **MinIO Console** | `https://minio-console.<tailnet>.ts.net` | S3 object storage UI |
| **MinIO S3 API** | `https://minio-s3.<tailnet>.ts.net` | S3-compatible API |

### Example Access

```bash
# From any device in your tailnet:
curl https://grafana.<your-tailnet>.ts.net

# Or just open in your browser:
open https://airflow.<your-tailnet>.ts.net
```

## Exposed Services

The following services have been configured with Tailscale ingress:

### Core Infrastructure
- **ArgoCD Server**: GitOps control plane
  - Hostname: `argocd`
  - Ports: 80 (HTTP), 443 (HTTPS)

### ML Platform
- **Airflow Webserver**: Workflow UI
  - Hostname: `airflow`
  - Port: 8080

- **MLflow**: Experiment tracking
  - Hostname: `mlflow`
  - Port: 5000

### Object Storage
- **MinIO Console**: Web UI
  - Hostname: `minio-console`
  - Port: 9001

- **MinIO S3 API**: S3-compatible storage
  - Hostname: `minio-s3`
  - Port: 9000

### Monitoring
- **Grafana**: Metrics dashboards
  - Hostname: `grafana`
  - Port: 80

- **Prometheus**: Metrics database
  - Hostname: `prometheus`
  - Port: 9090

## Troubleshooting

### Operator Not Starting

```bash
# Check operator logs
kubectl logs -n tailscale -l app.kubernetes.io/name=tailscale-operator

# Common issues:
# 1. OAuth secret not found - verify sealed secret was created
# 2. Invalid OAuth credentials - regenerate OAuth client
# 3. ACL policy not configured - check tailnet ACLs
```

### Services Not Appearing in Tailnet

```bash
# Check if services have the correct annotations
kubectl get svc -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.metadata.annotations.tailscale\.com/expose}{"\n"}{end}' | grep "true"

# Check operator logs for errors
kubectl logs -n tailscale -l app.kubernetes.io/name=tailscale-operator --tail=50

# Verify the service exists and has correct selector
kubectl get svc <service-name> -n <namespace> -o yaml
```

### Cannot Access Service via Tailscale URL

```bash
# 1. Verify device appears in tailnet
# Go to: https://login.tailscale.com/admin/machines

# 2. Check if you're connected to Tailscale
tailscale status

# 3. Verify DNS is working
nslookup airflow.<your-tailnet>.ts.net

# 4. Check service is running in Kubernetes
kubectl get pods -n <namespace>
kubectl get svc -n <namespace>
```

### Sealed Secret Issues

```bash
# Verify sealed secret was created
kubectl get sealedsecret operator-oauth -n tailscale

# Check if it was unsealed
kubectl get secret operator-oauth -n tailscale

# View sealed-secrets controller logs
kubectl logs -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets
```

## Security Considerations

1. **OAuth Credentials**: Keep your OAuth client secret secure. It's encrypted in the sealed secret.
2. **ACL Policy**: Restrict access to services using Tailscale ACLs
3. **Service Tags**: All services are tagged with `tag:k8s` for ACL filtering
4. **Network Policies**: Consider adding Kubernetes NetworkPolicies for defense in depth

## Advanced: Exposing Additional Services

To expose a new service via Tailscale:

1. Create a service definition with Tailscale annotations:

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: my-service
  namespace: my-namespace
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: "my-service"
    tailscale.com/tags: "tag:k8s"
spec:
  ports:
    - name: http
      port: 8080
      targetPort: 8080
  selector:
    app: my-service
```

2. Add to kustomization.yaml:

```yaml
resources:
  - ../../base
  - my-service-tailscale.yaml
```

3. Commit and push:

```bash
git add gitops/namespaces/my-namespace/
git commit -m "Add Tailscale ingress for my-service"
git push
```

## cert-manager Integration (Optional)

You can use cert-manager to automatically provision TLS certificates for your Tailscale services:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: airflow-tls
  namespace: airflow
spec:
  secretName: airflow-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - airflow.<your-tailnet>.ts.net
```

This combines Tailscale's secure networking with trusted TLS certificates.

## References

- [Tailscale Kubernetes Operator Docs](https://tailscale.com/kb/1236/kubernetes-operator)
- [Cluster Ingress Guide](https://tailscale.com/kb/1439/kubernetes-operator-cluster-ingress)
- [Tailscale ACL Policy](https://tailscale.com/kb/1018/acls)

## Summary

With Tailscale operator configured, you can:
- Access all ML Workbench services securely from anywhere
- No need for complex ingress controllers or load balancers
- Simple DNS names via MagicDNS
- Zero-config VPN access across all your devices
- Fine-grained access control via Tailscale ACLs

Your services are now accessible at `https://<service>.<tailnet>.ts.net` from any device in your tailnet!
