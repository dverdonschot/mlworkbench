#!/bin/bash
set -e

# MLWorkbench NFS Server Setup Script
# Sets up NFS server on Fedora host for Talos Kubernetes cluster shared storage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NFS_EXPORT_DIR="/srv/nfs/mlworkbench"
NFS_NETWORK="192.168.122.0/24"

echo "=========================================="
echo "  MLWorkbench NFS Server Setup"
echo "  Fedora Host Configuration"
echo "=========================================="
echo ""

# Check if running on Fedora
if [ ! -f /etc/fedora-release ]; then
    echo "[WARN] This script is designed for Fedora. Continuing anyway..."
fi

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] This script must be run as root or with sudo"
    echo "Usage: sudo $0"
    exit 1
fi

echo "[INFO] Step 1: Installing NFS server packages..."
dnf install -y nfs-utils

echo ""
echo "[INFO] Step 2: Creating NFS export directory..."
mkdir -p "$NFS_EXPORT_DIR"
chmod 777 "$NFS_EXPORT_DIR"  # Permissive for Kubernetes pods with different UIDs

echo ""
echo "[INFO] Step 3: Configuring NFS exports..."
EXPORT_LINE="$NFS_EXPORT_DIR $NFS_NETWORK(rw,sync,no_subtree_check,no_root_squash,insecure)"

# Backup existing exports file
if [ -f /etc/exports ]; then
    cp /etc/exports /etc/exports.backup.$(date +%Y%m%d-%H%M%S)
fi

# Check if export already exists
if grep -q "$NFS_EXPORT_DIR" /etc/exports 2>/dev/null; then
    echo "[INFO] Export already exists in /etc/exports, updating..."
    sed -i "\|$NFS_EXPORT_DIR|c\\$EXPORT_LINE" /etc/exports
else
    echo "[INFO] Adding new export to /etc/exports..."
    echo "$EXPORT_LINE" >> /etc/exports
fi

echo ""
echo "[INFO] Step 4: Configuring firewall..."
# Check if firewalld is running
if systemctl is-active --quiet firewalld; then
    echo "[INFO] Adding NFS services to firewall..."
    firewall-cmd --permanent --add-service=nfs
    firewall-cmd --permanent --add-service=rpc-bind
    firewall-cmd --permanent --add-service=mountd

    # Add the specific network zone if it doesn't exist
    if ! firewall-cmd --permanent --get-zones | grep -q libvirt; then
        echo "[INFO] Libvirt zone not found, adding rules to public zone..."
        firewall-cmd --permanent --zone=public --add-source=$NFS_NETWORK
    fi

    firewall-cmd --reload
    echo "[INFO] Firewall configured"
else
    echo "[WARN] firewalld is not running. Make sure NFS ports are accessible."
fi

echo ""
echo "[INFO] Step 5: Starting and enabling NFS server..."
systemctl enable --now nfs-server
systemctl restart nfs-server

echo ""
echo "[INFO] Step 6: Exporting NFS shares..."
exportfs -ra

echo ""
echo "[INFO] Step 7: Verifying NFS server status..."
systemctl status nfs-server --no-pager -l

echo ""
echo "=========================================="
echo "  NFS Server Setup Complete!"
echo "=========================================="
echo ""
echo "Export Details:"
echo "  Directory: $NFS_EXPORT_DIR"
echo "  Network:   $NFS_NETWORK"
echo "  Options:   rw,sync,no_subtree_check,no_root_squash,insecure"
echo ""
echo "Verify exports:"
echo "  showmount -e localhost"
echo ""
echo "Test from Talos nodes:"
echo "  showmount -e $(hostname -I | awk '{print $1}')"
echo ""
echo "Next steps:"
echo "  1. Verify Talos has NFS client support (likely already included)"
echo "  2. Deploy nfs-subdir-external-provisioner via ArgoCD"
echo "  3. Update storage classes to use NFS"
echo ""

# Show current exports
echo "Current NFS exports:"
exportfs -v
echo ""

# Get host IP for reference
HOST_IP=$(hostname -I | awk '{print $1}')
echo "[INFO] Your host IP appears to be: $HOST_IP"
echo "[INFO] Use this IP in your Kubernetes NFS provisioner configuration"
echo ""
