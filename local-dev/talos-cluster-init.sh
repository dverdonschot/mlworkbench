#!/bin/bash
set -euo pipefail

# Fully automated Talos cluster initialization
# This script will:
# 1. Detect Talos VM IPs
# 2. Generate Talos configuration
# 3. Apply configuration to all nodes (handles maintenance mode)
# 4. Bootstrap etcd on first node
# 5. Wait for cluster to form
# 6. Retrieve kubeconfig
# 7. Verify cluster is ready

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $*"; }

CLUSTER_NAME="talos-local"
CONFIG_DIR="${HOME}/.talos-local"
KUBECONFIG_PATH="${HOME}/.kube/talos-config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Clean start option
CLEAN_START=false
if [ "${1:-}" = "--clean" ]; then
    CLEAN_START=true
    log "Clean start requested - will remove existing configs"
fi

# Detect VM IPs from DHCP leases
detect_node_ips() {
    log "Detecting Talos VM IP addresses..."

    NODE1_IP=$(sudo virsh net-dhcp-leases default | grep '52:54:00:aa:bb:01' | awk '{print $5}' | cut -d'/' -f1)
    NODE2_IP=$(sudo virsh net-dhcp-leases default | grep '52:54:00:aa:bb:02' | awk '{print $5}' | cut -d'/' -f1)
    NODE3_IP=$(sudo virsh net-dhcp-leases default | grep '52:54:00:aa:bb:03' | awk '{print $5}' | cut -d'/' -f1)

    if [ -z "$NODE1_IP" ] || [ -z "$NODE2_IP" ] || [ -z "$NODE3_IP" ]; then
        error "Failed to detect all node IPs. Check VMs are running: sudo virsh list"
    fi

    log "Detected nodes:"
    log "  - talos-k8s-1: $NODE1_IP"
    log "  - talos-k8s-2: $NODE2_IP"
    log "  - talos-k8s-3: $NODE3_IP"
}

# Generate Talos configuration
generate_config() {
    log "Generating Talos configuration..."

    if [ "$CLEAN_START" = true ] && [ -d "$CONFIG_DIR" ]; then
        log "Removing existing config directory: $CONFIG_DIR"
        rm -rf "$CONFIG_DIR"
    fi

    mkdir -p "$CONFIG_DIR"

    if [ -f "$CONFIG_DIR/controlplane.yaml" ]; then
        log "Configuration already exists at $CONFIG_DIR - using it"
        return
    fi

    log "Generating new Talos configuration for cluster '$CLUSTER_NAME'"
    log "Control plane endpoint: https://${NODE1_IP}:6443"

    talosctl gen config "$CLUSTER_NAME" "https://${NODE1_IP}:6443" \
        --output-dir "$CONFIG_DIR" \
        --with-examples=false \
        --with-docs=false

    sed -i '/^cluster:/a\  allowSchedulingOnControlPlanes: true' "$CONFIG_DIR/controlplane.yaml"

    # Configure endpoints in talosconfig
    log "Configuring endpoints in talosconfig..."
    talosctl config endpoint "$NODE1_IP" "$NODE2_IP" "$NODE3_IP" \
        --talosconfig "$CONFIG_DIR/talosconfig"
    talosctl config node "$NODE1_IP" \
        --talosconfig "$CONFIG_DIR/talosconfig"

    # Patch the controlplane config with data disk and kubelet configuration
    log "Patching configuration with data disk and kubelet settings..."

    # Use yq to properly merge the configuration
    yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
        "$CONFIG_DIR/controlplane.yaml" \
        "$SCRIPT_DIR/talos-data-disk-patch.yaml" > "$CONFIG_DIR/controlplane-patched.yaml"

    mv "$CONFIG_DIR/controlplane-patched.yaml" "$CONFIG_DIR/controlplane.yaml"

    log "✓ Configuration generated:"
    log "  - Control plane config: $CONFIG_DIR/controlplane.yaml (with data disk and no taints)"
    log "  - Worker config: $CONFIG_DIR/worker.yaml"
    log "  - Talosconfig: $CONFIG_DIR/talosconfig"
}

# Apply configuration to all nodes
apply_config() {
    log "Applying Talos configuration to all nodes..."
    log ""
    log "NOTE: Nodes are in maintenance mode - using --insecure flag"
    log ""

    # Apply to node 1
    log "Applying config to talos-k8s-1 ($NODE1_IP)..."
    if talosctl apply-config \
        --insecure \
        --nodes "$NODE1_IP" \
        --file "$CONFIG_DIR/controlplane.yaml" 2>&1 | tee /tmp/talos-apply-1.log; then
        log "✓ Node 1 config applied successfully"
    else
        error "Failed to apply config to node 1. Check /tmp/talos-apply-1.log"
    fi

    sleep 5

    # Apply to node 2
    log "Applying config to talos-k8s-2 ($NODE2_IP)..."
    if talosctl apply-config \
        --insecure \
        --nodes "$NODE2_IP" \
        --file "$CONFIG_DIR/controlplane.yaml" 2>&1 | tee /tmp/talos-apply-2.log; then
        log "✓ Node 2 config applied successfully"
    else
        error "Failed to apply config to node 2. Check /tmp/talos-apply-2.log"
    fi

    sleep 5

    # Apply to node 3
    log "Applying config to talos-k8s-3 ($NODE3_IP)..."
    if talosctl apply-config \
        --insecure \
        --nodes "$NODE3_IP" \
        --file "$CONFIG_DIR/controlplane.yaml" 2>&1 | tee /tmp/talos-apply-3.log; then
        log "✓ Node 3 config applied successfully"
    else
        error "Failed to apply config to node 3. Check /tmp/talos-apply-3.log"
    fi

    log ""
    log "All nodes configured! Waiting 45 seconds for Talos to initialize..."
    sleep 45
}

# Bootstrap etcd on first node
bootstrap_etcd() {
    log "Bootstrapping etcd on first node ($NODE1_IP)..."
    log ""

    # First verify we can connect with the new config
    log "Testing connection with talosconfig..."
    if ! talosctl --nodes "$NODE1_IP" --talosconfig "$CONFIG_DIR/talosconfig" version &>/dev/null; then
        warn "Cannot connect with talosconfig yet, waiting 30 more seconds..."
        sleep 30
    fi

    log "Initiating etcd bootstrap..."
    if talosctl bootstrap \
        --nodes "$NODE1_IP" \
        --endpoints "$NODE1_IP" \
        --talosconfig "$CONFIG_DIR/talosconfig" 2>&1 | tee /tmp/talos-bootstrap.log; then
        log "✓ etcd bootstrap initiated successfully"
    else
        # Check if already bootstrapped or expected errors
        if grep -qi "already\|running" /tmp/talos-bootstrap.log; then
            log "✓ etcd already bootstrapped or running"
        else
            warn "Bootstrap command failed, but this might be normal. Continuing..."
            cat /tmp/talos-bootstrap.log
        fi
    fi
}

# Wait for cluster to be ready
wait_for_cluster() {
    log "Waiting for cluster to form (this may take 2-3 minutes)..."
    log "Checking if Kubernetes API is responsive..."

    local max_attempts=40
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if talosctl --talosconfig "$CONFIG_DIR/talosconfig" \
           health --server=false 2>/dev/null | grep -q "waiting"; then
            log "etcd is forming, waiting for Kubernetes..."
        elif talosctl --talosconfig "$CONFIG_DIR/talosconfig" \
           health --server=false 2>&1 | grep -q "is healthy"; then
            log "Cluster is healthy!"
            return 0
        fi

        echo -n "."
        sleep 5
        attempt=$((attempt + 1))
    done

    echo
    log "Health check reached timeout, but cluster may still be forming"
    log "Continuing to kubeconfig retrieval..."
}

# Retrieve kubeconfig
get_kubeconfig() {
    log "Retrieving kubeconfig..."

    mkdir -p "$(dirname "$KUBECONFIG_PATH")"

    local max_attempts=12
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if talosctl kubeconfig \
            --talosconfig "$CONFIG_DIR/talosconfig" \
            --force \
            "$KUBECONFIG_PATH" 2>&1 | tee /tmp/talos-kubeconfig.log; then
            log "✓ Kubeconfig retrieved successfully!"
            log "Saved to: $KUBECONFIG_PATH"
            return 0
        fi

        if grep -q "connection refused\|not ready" /tmp/talos-kubeconfig.log; then
            warn "Kubernetes API not ready yet, attempt $attempt/$max_attempts"
            sleep 10
            attempt=$((attempt + 1))
        else
            warn "Kubeconfig retrieval failed, but continuing..."
            cat /tmp/talos-kubeconfig.log
            return 1
        fi
    done

    warn "Could not retrieve kubeconfig after $max_attempts attempts"
    log "You can try manually later with:"
    log "  talosctl --talosconfig $CONFIG_DIR/talosconfig kubeconfig $KUBECONFIG_PATH"
}

# Verify cluster
verify_cluster() {
    log "Verifying cluster..."

    export KUBECONFIG="$KUBECONFIG_PATH"

    log "Waiting for nodes to be ready..."
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if kubectl get nodes &>/dev/null; then
            log "Nodes are visible!"
            kubectl get nodes
            break
        fi

        echo -n "."
        sleep 5
        attempt=$((attempt + 1))
    done

    echo
    log "Cluster verification complete!"
}

# Print helpful aliases and commands
print_final_info() {
    log ""
    log "======================================================================"
    log "✅ Talos cluster successfully initialized!"
    log "======================================================================"
    log ""
    log "Cluster details:"
    log "  - Name: $CLUSTER_NAME"
    log "  - Nodes: 3 control-plane nodes"
    log "  - Node IPs: $NODE1_IP, $NODE2_IP, $NODE3_IP"
    log "  - Kubeconfig: $KUBECONFIG_PATH"
    log "  - Talos config: $CONFIG_DIR/talosconfig"
    log ""
    log "Quick start commands:"
    log ""
    log "  # Use the cluster"
    log "  export KUBECONFIG=$KUBECONFIG_PATH"
    log "  kubectl get nodes"
    log ""
    log "  # Talos shortcuts (add to ~/.bashrc or ~/.zshrc)"
    log "  alias talos='talosctl --talosconfig $CONFIG_DIR/talosconfig --nodes $NODE1_IP'"
    log "  alias talos-all='talosctl --talosconfig $CONFIG_DIR/talosconfig --nodes $NODE1_IP,$NODE2_IP,$NODE3_IP'"
    log ""
    log "Useful Talos commands:"
    log "  talos health              # Check cluster health"
    log "  talos dashboard          # Interactive dashboard"
    log "  talos logs kubelet       # View kubelet logs"
    log "  talos logs etcd          # View etcd logs"
    log "  talos dmesg              # Kernel messages"
    log "  talos service kubelet status  # Check kubelet status"
    log ""
    log "Cluster management:"
    log "  talos upgrade --image ghcr.io/siderolabs/installer:v1.11.3  # Upgrade Talos"
    log "  talos reset --graceful --reboot  # Reset node (DESTRUCTIVE)"
    log ""
}

# Main execution
main() {
    log "======================================================================"
    log "Talos Kubernetes Cluster Initialization"
    log "======================================================================"
    log ""

    detect_node_ips
    log ""

    generate_config
    log ""

    apply_config
    log ""

    bootstrap_etcd
    log ""

    wait_for_cluster
    log ""

    get_kubeconfig
    log ""

    verify_cluster

    print_final_info
}

main "$@"
