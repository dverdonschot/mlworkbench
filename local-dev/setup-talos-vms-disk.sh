#!/bin/bash
set -euo pipefail

# Talos VM setup using disk image (not ISO)
# This method pre-installs Talos to disk so VMs boot correctly

TALOS_VERSION="v1.11.3"
TALOS_IMAGE_URL="https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/metal-amd64.raw.zst"
TALOS_IMAGE="/var/home/ewt/Downloads/talos-metal-amd64.raw.zst"
BASE_DIR="/var/lib/libvirt/images/talos-k3s"
NUM_NODES=3
MEMORY=16777216  # 16 GB in KiB
VCPUS=4
DISK_SIZE=50  # GB - OS disk
DATA_DISK_SIZE=50  # GB - Additional disk for persistent storage

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

check_dependencies() {
    log "Checking dependencies..."
    
    for cmd in virsh qemu-img wget zstd; do
        if ! command -v "$cmd" &> /dev/null; then
            error "$cmd is not installed."
        fi
    done
    
    if ! sudo systemctl is-active --quiet libvirtd; then
        log "Starting libvirtd..."
        sudo systemctl start libvirtd
    fi
    
    log "All dependencies found."
}

download_talos_image() {
    log "Checking for Talos disk image..."
    
    if [ -f "${TALOS_IMAGE%.zst}" ]; then
        log "Talos disk image already extracted: $(basename ${TALOS_IMAGE%.zst})"
        return
    fi
    
    if [ ! -f "$TALOS_IMAGE" ]; then
        log "Downloading Talos ${TALOS_VERSION} disk image (~170MB compressed)..."
        log "URL: $TALOS_IMAGE_URL"
        wget -O "$TALOS_IMAGE" "$TALOS_IMAGE_URL"
    fi
    
    log "Extracting Talos disk image (zstd compression)..."
    zstd -d "$TALOS_IMAGE" -o "${TALOS_IMAGE%.zst}"
    log "Talos image ready: $(basename ${TALOS_IMAGE%.zst})"
}

generate_vm_xml() {
    local node_name=$1
    local mac_suffix=$2
    local disk_path="${BASE_DIR}/${node_name}.qcow2"
    local data_disk_path="${BASE_DIR}/${node_name}-data.qcow2"
    local xml_path="/tmp/${node_name}.xml"
    
    cat > "$xml_path" <<EOF
<domain type='kvm'>
  <name>${node_name}</name>
  <memory unit='KiB'>${MEMORY}</memory>
  <vcpu placement='static'>${VCPUS}</vcpu>
  <os>
    <type arch='x86_64' machine='q35'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <cpu mode='host-passthrough'/>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>
    <!-- OS disk (vda) -->
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='${disk_path}'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <!-- Data disk (vdb) for persistent storage -->
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='${data_disk_path}'/>
      <target dev='vdb' bus='virtio'/>
    </disk>
    <interface type='network'>
      <mac address='52:54:00:aa:bb:${mac_suffix}'/>
      <source network='default'/>
      <model type='virtio'/>
    </interface>
    <serial type='pty'>
      <target type='isa-serial' port='0'>
        <model name='isa-serial'/>
      </target>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <graphics type='vnc' port='-1' autoport='yes' listen='127.0.0.1'>
      <listen type='address' address='127.0.0.1'/>
    </graphics>
    <video>
      <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/>
    </video>
  </devices>
</domain>
EOF
}

create_vm() {
    local node_name=$1
    local node_num=$2
    
    log "Creating VM: $node_name"
    
    # Create OS disk from Talos image
    local disk_path="${BASE_DIR}/${node_name}.qcow2"
    local talos_raw="${TALOS_IMAGE%.zst}"
    
    log "Converting Talos raw image to qcow2..."
    sudo qemu-img convert -f raw -O qcow2 "$talos_raw" "$disk_path"
    sudo qemu-img resize "$disk_path" "${DISK_SIZE}G"
    
    # Create dedicated data disk for persistent storage
    local data_disk_path="${BASE_DIR}/${node_name}-data.qcow2"
    log "Creating ${DATA_DISK_SIZE}GB data disk for persistent storage..."
    sudo qemu-img create -f qcow2 "$data_disk_path" "${DATA_DISK_SIZE}G"
    
    # Generate VM XML
    local mac_suffix=$(printf "%02d" "$node_num")
    generate_vm_xml "$node_name" "$mac_suffix"
    
    # Define and start VM
    sudo virsh define "/tmp/${node_name}.xml"
    sudo virsh start "$node_name"
    
    log "VM $node_name created and started (OS: ${DISK_SIZE}GB, Data: ${DATA_DISK_SIZE}GB)"
}

main() {
    log "Starting Talos k8s cluster setup (disk image method)..."
    
    check_dependencies
    download_talos_image
    
    # Create base directory
    sudo mkdir -p "$BASE_DIR"
    
    log "Creating $NUM_NODES VMs..."
    for i in $(seq 1 $NUM_NODES); do
        node_name="talos-k8s-${i}"
        
        # Check if VM already exists
        if sudo virsh list --all 2>/dev/null | grep -qw "$node_name"; then
            warn "VM $node_name already exists. Destroying and recreating..."
            sudo virsh destroy "$node_name" 2>/dev/null || true
            sudo virsh undefine "$node_name" --remove-all-storage 2>/dev/null || true
            sudo rm -f "${BASE_DIR}/${node_name}.qcow2"
        fi
        
        create_vm "$node_name" "$i"
    done
    
    log ""
    log "✓ All VMs created successfully!"
    log ""
    log "VMs are booting Talos Linux from disk (not ISO)"
    log ""
    log "Next step: Run the cluster initialization script"
    log "  ./talos-cluster-init.sh"
    log ""
}

main "$@"
