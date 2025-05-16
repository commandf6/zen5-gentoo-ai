#!/bin/bash
# =============================================================================
# 3-setup-lvm.sh - Configure LVM for OS and tensor storage
# =============================================================================

set -euo pipefail
trap 'echo "[!] Error on line $LINENO: $BASH_COMMAND"; exit 1' ERR

# Script directory detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Source functions
source "$SCRIPT_DIR/functions.sh"

# Configuration
MARKER="/tmp/.03-lvm.done"

main() {
    # Check if already done
    if check_marker "$MARKER"; then
        info "LVM already set up. Skipping."
        return 0
    fi

    # Parse configuration
    parse_config

    # Define device paths
    ROOT_LUKS="/dev/mapper/$LUKS_ROOT"
    TENSOR_A_DEVICE="/dev/mapper/$LUKS_TENSOR_A"
    TENSOR_B_DEVICE="/dev/mapper/$LUKS_TENSOR_B"

    # Basic checks
    verify_root_user
    check_device "$ROOT_LUKS"
    check_device "$TENSOR_A_DEVICE"
    check_device "$TENSOR_B_DEVICE"

    # Check for LVM tools
    check_command "pvcreate" "sys-fs/lvm2"
    check_command "vgcreate" "sys-fs/lvm2"
    check_command "lvcreate" "sys-fs/lvm2"

    info "Setting up Logical Volume Management (LVM)..."

    # Create OS LVM inside LUKS
    info "Setting up LVM for OS (root + encrypted swap)..."
    
    if ! confirm_action "Continue with OS LVM setup?"; then
        die "LVM setup aborted by user"
    fi
    
    # Create physical volume
    pvcreate "$ROOT_LUKS" || die "pvcreate $ROOT_LUKS failed"
    
    # Create volume group
    vgcreate "$VG_OS" "$ROOT_LUKS" || die "vgcreate $VG_OS failed"
    
    # Create logical volumes
    lvcreate -L "$SWAP_SIZE" -n "$LV_SWAP" "$VG_OS" || die "lvcreate swap failed"
    lvcreate -l 100%FREE -n "$LV_ROOT" "$VG_OS" || die "lvcreate root failed"
    
    info "OS LVM created: /dev/$VG_OS/$LV_SWAP and /dev/$VG_OS/$LV_ROOT"

    # Create mirrored tensor LVM
    info "Setting up mirrored LVM for tensor storage..."
    
    if ! confirm_action "Continue with mirrored tensor LVM setup?"; then
        die "Tensor LVM setup aborted by user"
    fi
    
    # Create physical volumes
    pvcreate "$TENSOR_A_DEVICE" "$TENSOR_B_DEVICE" || die "pvcreate tensor PVs failed"
    
    # Create volume group
    vgcreate "$VG_TENSOR" "$TENSOR_A_DEVICE" "$TENSOR_B_DEVICE" || die "vgcreate $VG_TENSOR failed"
    
    # Create mirrored logical volume
    lvcreate -m1 -l 100%FREE -n "$LV_TENSOR" "$VG_TENSOR" || die "lvcreate mirrored tensor LV failed"
    
    info "Tensor LVM mirrored: /dev/$VG_TENSOR/$LV_TENSOR"

    # Display LVM info
    info "LVM configuration summary:"
    
    echo
    echo "Volume Groups:"
    vgs
    
    echo
    echo "Logical Volumes:"
    lvs
    
    create_marker "$MARKER"
    info "LVM configuration complete"
}

# Execute main function
main "$@"