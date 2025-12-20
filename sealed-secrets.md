# Sealed Secrets Guide

This guide provides templates for creating all sealed secrets needed for the ML Workbench cluster.

## Prerequisites

1. **Sealed Secrets Controller**: Deployed via ArgoCD (gitops/argocd-apps/sealed-secrets.yaml)
2. **kubeseal CLI**: Installed locally

### Install kubeseal CLI

```bash
# Download and install kubeseal
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.34.0/kubeseal-0.34.0-linux-amd64.tar.gz
tar -xzf kubeseal-0.34.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
kubeseal --version
```

## Understanding Sealed Secrets

### How It Works

1. **Controller Installation**: The sealed-secrets controller creates a public/private key pair
2. **Encryption**: You use `kubeseal` CLI with the cluster's public key to encrypt secrets
3. **Storage**: Encrypted SealedSecrets are safe to commit to Git
4. **Decryption**: Only the controller (with the private key) can decrypt them in the cluster

### Important Concepts

- **Scope**: Secrets are scoped to namespace and name by default (most secure)
- **Format**: YAML format is human-readable and Git-friendly
- **Security**: The private key stays in the cluster; only encrypted data is in Git

## Backup and Restore the Root Certificate

### CRITICAL: Backup the Sealed Secrets Private Key

**Do this immediately after deploying the sealed-secrets controller!**

```bash
# Backup the encryption key (store in a SECURE location, NOT in Git!)
kubectl get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-master-key.yaml
```

**Storage recommendations:**
- Encrypted password manager (1Password, Bitwarden, etc.)
- Hardware security module (HSM)
- Encrypted backup drive
- Secure cloud storage with encryption

### Restore on New Cluster

If you need to restore the controller on a new cluster (or recover from disaster):

```bash
# 1. Apply the backed-up key BEFORE installing sealed-secrets controller
kubectl create namespace sealed-secrets
kubectl apply -f sealed-secrets-master-key.yaml

# 2. Install the controller (it will use the existing key)
# This happens automatically via ArgoCD

# 3. Verify the controller picked up the key
kubectl logs -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets

# 4. Test decryption with an existing sealed secret
kubectl apply -f gitops/sealed-secrets/databases/redis-sealed.yaml
kubectl get secret -n databases redis
```

## Secret Templates

Replace `YOUR_SECURE_*_PASSWORD` with your actual secure passwords before running the commands.

---

### 1. Redis Password

**Location**: `gitops/sealed-secrets/databases/redis-sealed.yaml`
**Namespace**: `databases`
**Used by**: Redis standalone instance

```bash
kubectl create secret generic redis \
  --from-literal=password=YOUR_SECURE_REDIS_PASSWORD \
  --namespace=databases \
  --dry-run=client -o yaml | \
kubeseal --format yaml --controller-namespace sealed-secrets \
  > gitops/sealed-secrets/databases/redis-sealed.yaml
```

---

### 2. PostgreSQL Root Password

**Location**: `gitops/sealed-secrets/databases/postgresql-sealed.yaml`
**Namespace**: `databases`
**Used by**: PostgreSQL primary instance (root user)
**Current plaintext value**: `postgres` (gitops/argocd-apps/postgresql.yaml:20)

```bash
kubectl create secret generic postgresql \
  --from-literal=postgres-password=YOUR_SECURE_POSTGRES_ROOT_PASSWORD \
  --from-literal=password=YOUR_SECURE_POSTGRES_ROOT_PASSWORD \
  --namespace=databases \
  --dry-run=client -o yaml | \
kubeseal --format yaml --controller-namespace sealed-secrets \
  > gitops/sealed-secrets/databases/postgresql-sealed.yaml
```

**Note**: Both `postgres-password` and `password` keys are required by the Bitnami PostgreSQL chart.

---

### 3. PostgreSQL Init Scripts

**Location**: `gitops/sealed-secrets/databases/postgresql-init-scripts-sealed.yaml`
**Namespace**: `databases`
**Used by**: PostgreSQL initdb to create database users with secure passwords
**Current plaintext values**: Hardcoded in init.sql (gitops/argocd-apps/postgresql.yaml:46-48)

```bash
# First, create the init script that references environment variables
# These env vars will be populated from the user secrets below

cat <<'EOF' > /tmp/init.sql
-- Create databases for different services
CREATE DATABASE mlflow;
CREATE DATABASE airflow;
CREATE DATABASE mlworkbench;

-- Create users with passwords from environment variables
-- Note: We'll use a shell script instead to access env vars
EOF

cat <<'EOF' > /tmp/init.sh
#!/bin/bash
set -e

# Read passwords from secrets mounted as environment variables
MLFLOW_PASSWORD="${MLFLOW_DB_PASSWORD}"
AIRFLOW_PASSWORD="${AIRFLOW_DB_PASSWORD}"
MLWORKBENCH_PASSWORD="${MLWORKBENCH_DB_PASSWORD}"

# Execute SQL commands
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create databases
    CREATE DATABASE mlflow;
    CREATE DATABASE airflow;
    CREATE DATABASE mlworkbench;

    -- Create users
    CREATE USER mlflow WITH PASSWORD '$MLFLOW_PASSWORD';
    CREATE USER airflow WITH PASSWORD '$AIRFLOW_PASSWORD';
    CREATE USER mlworkbench WITH PASSWORD '$MLWORKBENCH_PASSWORD';

    -- Grant privileges
    GRANT ALL PRIVILEGES ON DATABASE mlflow TO mlflow;
    GRANT ALL PRIVILEGES ON DATABASE airflow TO airflow;
    GRANT ALL PRIVILEGES ON DATABASE mlworkbench TO mlworkbench;
EOSQL
EOF

# Create the secret with the init script
kubectl create secret generic postgresql-init-scripts \
  --from-file=init.sh=/tmp/init.sh \
  --namespace=databases \
  --dry-run=client -o yaml | \
kubeseal --format yaml --controller-namespace sealed-secrets \
  > gitops/sealed-secrets/databases/postgresql-init-scripts-sealed.yaml

# Clean up temp files
rm /tmp/init.sh
```

**Note**: This script will use environment variables that come from the user secrets below.

---

### 4. PostgreSQL - MLflow User

**Location**: `gitops/sealed-secrets/databases/postgresql-mlflow-user-sealed.yaml`
**Namespace**: `databases`
**Used by**: PostgreSQL init script for MLflow database user
**Current plaintext value**: `mlflow` (gitops/argocd-apps/postgresql.yaml:46)

```bash
kubectl create secret generic postgresql-mlflow-user \
  --from-literal=username=mlflow \
  --from-literal=password=YOUR_SECURE_MLFLOW_DB_PASSWORD \
  --namespace=databases \
  --dry-run=client -o yaml | \
kubeseal --format yaml --controller-namespace sealed-secrets \
  > gitops/sealed-secrets/databases/postgresql-mlflow-user-sealed.yaml
```

---

### 5. PostgreSQL - Airflow User

**Location**: `gitops/sealed-secrets/databases/postgresql-airflow-user-sealed.yaml`
**Namespace**: `databases`
**Used by**: PostgreSQL init script for Airflow database user
**Current plaintext value**: `airflow` (gitops/argocd-apps/postgresql.yaml:47)

```bash
kubectl create secret generic postgresql-airflow-user \
  --from-literal=username=airflow \
  --from-literal=password=YOUR_SECURE_AIRFLOW_DB_PASSWORD \
  --namespace=databases \
  --dry-run=client -o yaml | \
kubeseal --format yaml --controller-namespace sealed-secrets \
  > gitops/sealed-secrets/databases/postgresql-airflow-user-sealed.yaml
```

---

### 6. PostgreSQL - MLWorkbench User

**Location**: `gitops/sealed-secrets/databases/postgresql-mlworkbench-user-sealed.yaml`
**Namespace**: `databases`
**Used by**: PostgreSQL init script for MLWorkbench database user
**Current plaintext value**: `mlworkbench` (gitops/argocd-apps/postgresql.yaml:48)

```bash
kubectl create secret generic postgresql-mlworkbench-user \
  --from-literal=username=mlworkbench \
  --from-literal=password=YOUR_SECURE_MLWORKBENCH_DB_PASSWORD \
  --namespace=databases \
  --dry-run=client -o yaml | \
kubeseal --format yaml --controller-namespace sealed-secrets \
  > gitops/sealed-secrets/databases/postgresql-mlworkbench-user-sealed.yaml
```

---

### 7. MinIO Root Credentials

**Location**: `gitops/namespaces/minio/base/minio-root-credentials-sealed.yaml`
**Namespace**: `minio`
**Used by**: MinIO server root user
**Required keys**: `rootUser`, `rootPassword`

```bash
kubectl create secret generic minio-root-credentials \
  --from-literal=rootUser=admin \
  --from-literal=rootPassword=YOUR_SECURE_MINIO_ROOT_PASSWORD \
  --namespace=minio \
  --dry-run=client -o yaml | \
kubeseal --format yaml --controller-name=sealed-secrets-controller --controller-namespace=sealed-secrets \
  > gitops/namespaces/minio/base/minio-root-credentials-sealed.yaml
```

**Note**: This secret is stored in the MinIO namespace manifests and included in the kustomization.yaml

---

### 8. MinIO - MLflow User

**Location**: `gitops/sealed-secrets/minio/mlflow-user-sealed.yaml`
**Namespace**: `minio`
**Used by**: MLflow for S3-compatible artifact storage
**Current plaintext values**: `mlflow` / `mlflow123` (gitops/argocd-apps/minio.yaml:61-62)

```bash
kubectl create secret generic minio-mlflow-user \
  --from-literal=accessKey=mlflow \
  --from-literal=secretKey=YOUR_SECURE_MLFLOW_MINIO_PASSWORD \
  --namespace=minio \
  --dry-run=client -o yaml | \
kubeseal --format yaml --controller-namespace sealed-secrets \
  > gitops/sealed-secrets/minio/mlflow-user-sealed.yaml
```

---

### 9. MinIO - Airflow User

**Location**: `gitops/sealed-secrets/minio/airflow-user-sealed.yaml`
**Namespace**: `minio`
**Used by**: Airflow for log storage and XCom backend
**Current plaintext values**: `airflow` / `airflow123` (gitops/argocd-apps/minio.yaml:64-65)

```bash
kubectl create secret generic minio-airflow-user \
  --from-literal=accessKey=airflow \
  --from-literal=secretKey=YOUR_SECURE_AIRFLOW_MINIO_PASSWORD \
  --namespace=minio \
  --dry-run=client -o yaml | \
kubeseal --format yaml --controller-namespace sealed-secrets \
  > gitops/sealed-secrets/minio/airflow-user-sealed.yaml
```

---

### 10. MLflow Environment Secrets

**Location**: `gitops/sealed-secrets/mlflow/env-secrets-sealed.yaml`
**Namespace**: `mlflow`
**Used by**: MLflow server for database and S3 connections
**Current plaintext values**: Various (gitops/argocd-apps/mlflow.yaml:32,38-39)

```bash
# Use the passwords you created above for PostgreSQL MLflow user and MinIO MLflow user
kubectl create secret generic mlflow-env-secret \
  --from-literal=POSTGRES_PASSWORD=YOUR_SECURE_MLFLOW_DB_PASSWORD \
  --from-literal=AWS_ACCESS_KEY_ID=mlflow \
  --from-literal=AWS_SECRET_ACCESS_KEY=YOUR_SECURE_MLFLOW_MINIO_PASSWORD \
  --namespace=mlflow \
  --dry-run=client -o yaml | \
kubeseal --format yaml --controller-namespace sealed-secrets \
  > gitops/sealed-secrets/mlflow/env-secrets-sealed.yaml
```

---

### 11. Tailscale OAuth Client

**Location**: `gitops/namespaces/tailscale/base/operator-oauth-sealed.yaml`
**Namespace**: `tailscale`
**Used by**: Tailscale Kubernetes operator to authenticate with your tailnet
**Prerequisites**: Create OAuth client at https://login.tailscale.com/admin/settings/oauth

#### Creating the OAuth Client

1. Go to https://login.tailscale.com/admin/settings/oauth
2. Click **Generate OAuth Client**
3. Add scopes: `Devices: Write`, `Auth Keys: Write`, `Services: Write`
4. Save the Client ID and Client Secret

#### Creating the Sealed Secret

```bash
# Replace with your actual OAuth credentials
kubectl create secret generic operator-oauth \
  --from-literal=client_id=YOUR_TAILSCALE_OAUTH_CLIENT_ID \
  --from-literal=client_secret=YOUR_TAILSCALE_OAUTH_CLIENT_SECRET \
  --namespace=tailscale \
  --dry-run=client -o yaml | \
kubeseal --format yaml --controller-namespace sealed-secrets \
  > gitops/namespaces/tailscale/base/operator-oauth-sealed.yaml
```

**Note**: The operator uses OAuth credentials (not auth keys) for better security and automatic device management.

---

### 12. Airflow Metadata Connection

**Location**: `gitops/sealed-secrets/airflow/metadata-sealed.yaml`
**Namespace**: `airflow`
**Used by**: Airflow to connect to its metadata database

```bash
# Use the password you created above for PostgreSQL Airflow user
# Update PASSWORD in the connection string below
kubectl create secret generic airflow-metadata \
  --from-literal=connection='postgresql://airflow:YOUR_SECURE_AIRFLOW_DB_PASSWORD@postgresql.databases:5432/airflow?sslmode=disable' \
  --namespace=airflow \
  --dry-run=client -o yaml | \
kubeseal --format yaml --controller-namespace sealed-secrets \
  > gitops/sealed-secrets/airflow/metadata-sealed.yaml
```

---

## Workflow

### Initial Setup

1. **Deploy Sealed Secrets Controller** (via ArgoCD):
```bash
# Add sealed-secrets to root-app.yaml or apply directly
kubectl apply -f gitops/argocd-apps/sealed-secrets.yaml

# Wait for controller to be ready
kubectl wait --for=condition=available --timeout=120s \
  deployment/sealed-secrets-controller -n sealed-secrets
```

2. **Backup the Master Key** (see above - CRITICAL!)

3. **Generate All Sealed Secrets**:
```bash
# Run all the commands above with your secure passwords
# This will create all files in gitops/sealed-secrets/
```

4. **Commit to Git**:
```bash
git add gitops/sealed-secrets/
git commit -m "Add sealed secrets for all services"
git push
```

5. **Verify Secrets Created**:
```bash
# ArgoCD will automatically sync and create the secrets
# Verify they were created:
kubectl get sealedsecrets -A
kubectl get secrets -A | grep -E 'redis|postgresql|minio|mlflow|airflow'
```

### Updating a Secret

To rotate or update a secret:

1. Generate a new sealed secret with the updated value
2. Overwrite the existing file in gitops/sealed-secrets/
3. Commit and push to Git
4. ArgoCD will sync and update the secret
5. Restart affected pods to pick up the new secret:
```bash
kubectl rollout restart deployment/<deployment-name> -n <namespace>
```

### Disaster Recovery

If you lose your cluster but have the master key backup:

1. Create a new cluster
2. Install ArgoCD
3. **BEFORE** deploying sealed-secrets app, restore the master key:
```bash
kubectl create namespace sealed-secrets
kubectl apply -f sealed-secrets-master-key.yaml
```
4. Deploy the sealed-secrets ArgoCD application
5. Deploy your other applications - they will be able to decrypt the sealed secrets

## Security Best Practices

1. **Never commit plaintext secrets** to Git
2. **Always backup the master key** in a secure, encrypted location
3. **Use strong passwords**: Consider using a password generator
4. **Rotate secrets regularly**: Especially after team member changes
5. **Limit access**: Only cluster admins should have access to unsealed secrets
6. **Monitor**: Set up alerts for sealed-secrets controller failures

## Troubleshooting

### Controller not starting
```bash
kubectl logs -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets
kubectl describe pod -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets
```

### Sealed secret not creating regular secret
```bash
kubectl get sealedsecret <name> -n <namespace> -o yaml
kubectl describe sealedsecret <name> -n <namespace>
kubectl logs -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets
```

### Re-encrypt existing secret
```bash
kubectl get secret <name> -n <namespace> -o yaml | \
kubeseal --format yaml --controller-namespace sealed-secrets \
  > new-sealed-secret.yaml
```

### Verify encryption
```bash
# The encrypted data should be different from the original
cat gitops/sealed-secrets/databases/redis-sealed.yaml
# You should see base64 encrypted data, not plaintext
```

## Summary

After running all commands above, you should have these sealed secrets committed to Git:

**Database Secrets (databases namespace):**
- ✅ `gitops/sealed-secrets/databases/redis-sealed.yaml`
- ✅ `gitops/sealed-secrets/databases/postgresql-sealed.yaml`
- ✅ `gitops/sealed-secrets/databases/postgresql-init-scripts-sealed.yaml`
- ✅ `gitops/sealed-secrets/databases/postgresql-mlflow-user-sealed.yaml`
- ✅ `gitops/sealed-secrets/databases/postgresql-airflow-user-sealed.yaml`
- ✅ `gitops/sealed-secrets/databases/postgresql-mlworkbench-user-sealed.yaml`

**MinIO Secrets (minio namespace):**
- ✅ `gitops/namespaces/minio/base/minio-root-credentials-sealed.yaml`
- ✅ `gitops/sealed-secrets/minio/mlflow-user-sealed.yaml`
- ✅ `gitops/sealed-secrets/minio/airflow-user-sealed.yaml`

**Application Secrets:**
- ✅ `gitops/sealed-secrets/mlflow/env-secrets-sealed.yaml` (mlflow namespace)
- ✅ `gitops/sealed-secrets/airflow/metadata-sealed.yaml` (airflow namespace)

**Tailscale Secrets (tailscale namespace):**
- ✅ `gitops/namespaces/tailscale/base/operator-oauth-sealed.yaml`

**Total: 12 sealed secrets - All safe to commit to Git!**

Once committed, ArgoCD will automatically sync them and the sealed-secrets controller will decrypt them in the cluster.
