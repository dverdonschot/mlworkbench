#!/bin/bash
set -euo pipefail

# Bootstrap script for MLWorkbench Federated Learning Platform on Talos Linux
# This script automates the initial setup of Talos Kubernetes with ArgoCD

echo "🚀 Starting MLWorkbench GitOps bootstrap for Talos..."

# Configuration
GATEWAY_API_VERSION="v1.2.1"
KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/talos-config}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    command -v kubectl >/dev/null 2>&1 || log_error "kubectl is not installed"
    command -v talosctl >/dev/null 2>&1 || log_error "talosctl is not installed"
    command -v argocd >/dev/null 2>&1 || log_warn "argocd CLI not installed (optional but recommended)"

    # Check if kubeconfig exists
    if [ ! -f "$KUBECONFIG" ]; then
        log_error "Kubeconfig not found at $KUBECONFIG. Please run talos-cluster-init.sh first."
    fi

    log_info "✓ All prerequisites met"
}

check_cluster() {
    log_info "Checking Talos Kubernetes cluster..."

    export KUBECONFIG="$KUBECONFIG"

    if ! kubectl get nodes >/dev/null 2>&1; then
        log_error "Kubernetes cluster is not accessible. Please ensure Talos cluster is initialized."
    fi

    # Verify Talos
    if kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.osImage}' 2>/dev/null | grep -qi "talos"; then
        log_info "✓ Talos Kubernetes cluster detected"

        # Show cluster info
        NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
        log_info "  Nodes: $NODE_COUNT"

        kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[3].type,ROLES:.metadata.labels.node-role\\.kubernetes\\.io/control-plane,VERSION:.status.nodeInfo.kubeletVersion --no-headers | while read -r line; do
            log_debug "  $line"
        done
    else
        log_warn "Not a Talos cluster - proceeding anyway"
    fi
}

install_gateway_api_crds() {
    log_info "Installing Gateway API CRDs..."

    # Check if CRDs are already installed
    if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
        log_info "✓ Gateway API CRDs already installed"
        GATEWAY_VERSION=$(kubectl get crd gateways.gateway.networking.k8s.io -o jsonpath='{.metadata.labels.gateway\.networking\.k8s\.io/bundle-version}' 2>/dev/null || echo "unknown")
        log_debug "  Version: $GATEWAY_VERSION"
        return
    fi

    # Install Gateway API CRDs (required for Envoy Gateway and HTTPRoute resources)
    log_info "Installing Gateway API $GATEWAY_API_VERSION..."
    kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

    # Wait for CRDs to be established
    log_info "Waiting for Gateway API CRDs to be ready..."
    kubectl wait --for condition=established --timeout=60s crd/gateways.gateway.networking.k8s.io

    log_info "✓ Gateway API CRDs installed successfully"
}

create_argocd_namespace() {
    log_info "Creating argocd namespace..."

    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

    log_info "✓ Namespace created"
}

deploy_argocd() {
    log_info "Deploying ArgoCD..."

    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    GITOPS_DIR="$SCRIPT_DIR/.."

    kubectl apply -k "$GITOPS_DIR/namespaces/argocd/overlays/default/"

    log_info "Waiting for ArgoCD to be ready (this may take 2-3 minutes)..."

    # Wait for ArgoCD server
    if kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=argocd-server \
        -n argocd \
        --timeout=300s; then
        log_info "✓ ArgoCD deployed successfully"
    else
        log_error "ArgoCD pods failed to start. Check: kubectl get pods -n argocd"
    fi
}

get_argocd_password() {
    log_info "Retrieving ArgoCD admin password..."

    # Wait a moment for secret to be created
    sleep 2

    PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

    if [ -z "$PASSWORD" ]; then
        log_warn "Could not retrieve password. It may take a few seconds to generate."
        echo ""
        echo "Run this command in a moment:"
        echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d && echo"
        echo ""
        return
    fi

    echo ""
    echo "=========================================="
    echo "ArgoCD Credentials:"
    echo "Username: admin"
    echo "Password: $PASSWORD"
    echo "=========================================="
    echo ""

    # Save to file for convenience
    echo "$PASSWORD" > /tmp/argocd-admin-password.txt
    log_info "Password saved to: /tmp/argocd-admin-password.txt"
}

get_argocd_url() {
    log_info "ArgoCD access information:"

    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

    echo ""
    echo "Access ArgoCD UI:"
    echo ""
    echo "Option 1 - NodePort (Talos local cluster):"
    echo "  https://$NODE_IP:30443"
    echo ""
    echo "Option 2 - Port forward (recommended):"
    echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "  Then open: https://localhost:8080"
    echo ""
    echo "Option 3 - Via kubectl proxy:"
    echo "  kubectl proxy"
    echo "  Then open: http://localhost:8001/api/v1/namespaces/argocd/services/https:argocd-server:https/proxy/"
    echo ""
}

setup_argocd_cli() {
    if ! command -v argocd >/dev/null 2>&1; then
        log_warn "ArgoCD CLI not installed. Install with:"
        echo ""
        echo "  # Linux AMD64"
        echo "  curl -sSL https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 -o argocd"
        echo "  chmod +x argocd && sudo mv argocd /usr/local/bin/"
        echo ""
        echo "  # Linux ARM64"
        echo "  curl -sSL https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-arm64 -o argocd"
        echo "  chmod +x argocd && sudo mv argocd /usr/local/bin/"
        echo ""
        return
    fi

    log_info "ArgoCD CLI available"

    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    ARGOCD_SERVER="$NODE_IP:30443"

    echo ""
    echo "To login via CLI:"
    echo "  argocd login $ARGOCD_SERVER --insecure --username admin --password \$(cat /tmp/argocd-admin-password.txt)"
    echo ""
    echo "Or manually:"
    echo "  argocd login $ARGOCD_SERVER --insecure"
    echo ""
}

create_bootstrap_secrets() {
    log_info "Setting up bootstrap secrets namespace..."

    # Create mlworkbench namespace for bootstrap secrets
    kubectl create namespace mlworkbench --dry-run=client -o yaml | kubectl apply -f -

    echo ""
    log_warn "⚠️  IMPORTANT: Bootstrap Secrets Setup Required"
    echo ""
    echo "Before deploying applications, you need to create bootstrap secrets."
    echo "These will be replaced by Infisical once it's deployed (optional)."
    echo ""
    echo "Run the following commands to create bootstrap secrets:"
    echo ""
    echo "  # Set your actual values"
    echo "  HUGGINGFACE_TOKEN=\"your-huggingface-token\""
    echo "  TAILSCALE_CLIENT_ID=\"your-tailscale-client-id\""
    echo "  TAILSCALE_CLIENT_SECRET=\"your-tailscale-client-secret\""
    echo "  AWS_ACCESS_KEY_ID=\"your-s3-access-key\""
    echo "  AWS_SECRET_ACCESS_KEY=\"your-s3-secret-key\""
    echo ""
    echo "  # Create the secret"
    echo "  kubectl create secret generic mlworkbench-env \\"
    echo "    --from-literal=HUGGINGFACE_TOKEN=\"\$HUGGINGFACE_TOKEN\" \\"
    echo "    --from-literal=TAILSCALE_CLIENT_ID=\"\$TAILSCALE_CLIENT_ID\" \\"
    echo "    --from-literal=TAILSCALE_CLIENT_SECRET=\"\$TAILSCALE_CLIENT_SECRET\" \\"
    echo "    --from-literal=AWS_ACCESS_KEY_ID=\"\$AWS_ACCESS_KEY_ID\" \\"
    echo "    --from-literal=AWS_SECRET_ACCESS_KEY=\"\$AWS_SECRET_ACCESS_KEY\" \\"
    echo "    --namespace=mlworkbench \\"
    echo "    --dry-run=client -o yaml | kubectl apply -f -"
    echo ""
    echo "Or minimal setup (skip optional secrets):"
    echo ""
    echo "  kubectl create secret generic mlworkbench-env \\"
    echo "    --from-literal=HUGGINGFACE_TOKEN=\"\$HUGGINGFACE_TOKEN\" \\"
    echo "    --namespace=mlworkbench"
    echo ""
}

setup_infisical_info() {
    echo ""
    log_info "📦 Infisical Setup (Post-Bootstrap)"
    echo ""
    echo "After deploying the root app, Infisical will be available for secrets management."
    echo ""
    echo "To access Infisical:"
    echo "  1. Wait for Infisical pods to be ready:"
    echo "     kubectl get pods -n monitoring -l app.kubernetes.io/name=infisical"
    echo ""
    echo "  2. Port-forward to access UI:"
    echo "     kubectl port-forward -n monitoring svc/infisical-frontend 8082:80"
    echo ""
    echo "  3. Open http://localhost:8082 and complete initial setup"
    echo ""
    echo "  4. Create project 'mlworkbench-local' with environment 'dev'"
    echo ""
    echo "  5. Add your secrets to Infisical"
    echo ""
    echo "  6. Update External Secrets to use Infisical provider (see docs)"
    echo ""
}

update_repository_urls() {
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    ARGOCD_APPS_DIR="$SCRIPT_DIR/../argocd-apps"

    echo ""
    log_warn "⚠️  Repository URL Update Required"
    echo ""
    echo "Before deploying the root app, update repository URLs:"
    echo ""
    echo "  cd $ARGOCD_APPS_DIR"
    echo ""
    echo "  # Replace 'mlworkbench-com' with your GitHub username/org"
    echo "  find . -name '*.yaml' -type f -exec sed -i 's|mlworkbench-com|YOUR_USERNAME|g' {} +"
    echo ""
    echo "Or add your git repository to ArgoCD via CLI:"
    echo ""
    echo "  argocd repo add https://github.com/YOUR_USERNAME/mlworkbench.git \\"
    echo "    --username YOUR_USERNAME \\"
    echo "    --password YOUR_GITHUB_PAT"
    echo ""
}

prompt_next_steps() {
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

    echo ""
    log_info "📋 Next Steps:"
    echo ""
    echo "1. ✅ Access ArgoCD UI and login (credentials above)"
    echo ""
    echo "2. ⚙️  Create bootstrap secrets (commands above)"
    echo ""
    echo "3. 🔧 Update repository URLs in ArgoCD applications"
    echo ""
    echo "4. 🚀 Deploy all applications via root app:"
    echo "     kubectl apply -f $SCRIPT_DIR/../argocd-apps/argocd-root-app.yaml"
    echo ""
    echo "5. 👀 Watch deployment progress:"
    echo "     kubectl get applications -n argocd -w"
    echo "   Or monitor in ArgoCD UI"
    echo ""
    echo "6. 📊 Access deployed services:"
    echo "     kubectl get pods -A"
    echo "     kubectl get svc -A"
    echo ""
    echo "7. 🔐 Setup Infisical for production secrets management"
    echo ""
    echo "For detailed instructions, see:"
    echo "  - Bootstrap guide: $SCRIPT_DIR/README.md"
    echo "  - Talos guide: $SCRIPT_DIR/TALOS_BOOTSTRAP.md"
    echo ""
}

print_cluster_info() {
    echo ""
    log_info "🎯 Cluster Information"
    echo ""
    echo "Environment variables to set:"
    echo "  export KUBECONFIG=$KUBECONFIG"
    echo ""
    echo "Useful commands:"
    echo "  kubectl get nodes                    # View cluster nodes"
    echo "  kubectl get pods -A                  # View all pods"
    echo "  kubectl get applications -n argocd  # View ArgoCD applications"
    echo ""
    echo "Talos-specific commands:"
    echo "  talosctl --talosconfig ~/.talos-local/talosconfig health"
    echo "  talosctl --talosconfig ~/.talos-local/talosconfig dashboard"
    echo ""
}

main() {
    echo ""
    echo "=========================================="
    echo "  Talos GitOps Bootstrap"
    echo "  MLWorkbench Federated Learning Platform"
    echo "=========================================="
    echo ""

    check_prerequisites
    echo ""

    check_cluster
    echo ""

    install_gateway_api_crds
    echo ""

    create_argocd_namespace
    echo ""

    deploy_argocd
    echo ""

    get_argocd_password
    echo ""

    get_argocd_url
    echo ""

    setup_argocd_cli
    echo ""

    create_bootstrap_secrets
    echo ""

    setup_infisical_info
    echo ""

    update_repository_urls
    echo ""

    print_cluster_info
    echo ""

    prompt_next_steps
    echo ""

    log_info "🎉 Bootstrap complete!"
    echo ""
    log_info "Your Talos Kubernetes cluster is ready for GitOps deployment!"
    echo ""
}

main "$@"
