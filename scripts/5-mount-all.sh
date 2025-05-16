#!/bin/bash
# =============================================================================
# 5-mount-all.sh - Mount all filesystems and activate encrypted swap
# =============================================================================

set -euo pipefail
trap 'echo "[!] Error on line $LINENO: $BASH_COMMAND"; exit 1' ERR

# Use fixed paths instead of dynamic detection
INSTALL_DIR="/tmp/zen5-gentoo-ai"
SCRIPTS_DIR="${INSTALL_DIR}/scripts"

# Source functions
source "${SCRIPTS_DIR}/functions.sh"

# Configuration
MARKER="/tmp/.05-mounts.done"
MOUNT_ROOT="/mnt/gentoo"

main() {
    # Check if already done
    if check_marker "$MARKER"; then
        info "Filesystems already mounted. Skipping."
        return 0
    fi

    # Parse configuration
    parse_config

    # Define device paths
    EFI_PARTITION="${DISK0}p1"
    BOOT_PARTITION="${DISK0}p2"
    ROOT_DEVICE="/dev/mapper/${VG_OS}-${LV_ROOT}"
    SWAP_DEVICE="/dev/mapper/${VG_OS}-${LV_SWAP}"
    TENSOR_DEVICE="/dev/mapper/${VG_TENSOR}-${LV_TENSOR}"

    # Basic checks
    verify_root_user
    check_device "$EFI_PARTITION"
    check_device "$BOOT_PARTITION"
    check_device "$ROOT_DEVICE"
    check_device "$SWAP_DEVICE"
    check_device "$TENSOR_DEVICE"

    # Check required commands
    check_command "mount" "sys-apps/util-linux"
    check_command "swapon" "sys-apps/util-linux"
    check_command "mkdir" "sys-apps/coreutils"

    info "Mounting filesystems..."

    # Create mount point
    mkdir -p "$MOUNT_ROOT"

    # Mount root filesystem
    info "Mounting root filesystem..."
    mount "$ROOT_DEVICE" "$MOUNT_ROOT" || die "Failed to mount root filesystem"

    # Create additional mount points
    mkdir -p "$MOUNT_ROOT"/{boot,boot/efi,home,.snapshots,tensor_lab}

    # Mount boot and EFI partitions
    info "Mounting boot partitions..."
    mount "$BOOT_PARTITION" "$MOUNT_ROOT/boot" || die "Failed to mount boot partition"
    mount "$EFI_PARTITION" "$MOUNT_ROOT/boot/efi" || die "Failed to mount EFI partition"

    # Mount subvolumes
    info "Mounting Btrfs subvolumes..."
    mount -o subvol=@home "$ROOT_DEVICE" "$MOUNT_ROOT/home" || warn "Failed to mount home subvolume"
    mount -o subvol=@snapshots "$ROOT_DEVICE" "$MOUNT_ROOT/.snapshots" || warn "Failed to mount snapshots subvolume"

    # Mount tensor lab filesystem
    info "Mounting tensor_lab filesystem..."
    mount "$TENSOR_DEVICE" "$MOUNT_ROOT/tensor_lab" || die "Failed to mount tensor_lab filesystem"

    # Create Portage TMPDIR
    info "Creating Portage TMPDIR on tensor_lab..."
    mkdir -p "$MOUNT_ROOT/tensor_lab/var/tmp/portage"

    # Activate swap
    info "Activating encrypted swap..."
    swapon "$SWAP_DEVICE" || warn "Failed to enable swap (non-fatal)"

    # Create pseudo-filesystem mount points for chroot
    info "Creating directories for pseudo-filesystems..."
    mkdir -p "$MOUNT_ROOT"/{proc,sys,dev,run,tmp}

    # Display mount status
    info "Current mount status:"
    findmnt -R "$MOUNT_ROOT" || mount | grep "$MOUNT_ROOT"
    
    echo
    info "Swap status:"
    swapon --show || cat /proc/swaps

    create_marker "$MARKER"
    info "All filesystems mounted successfully"
}

# Execute main function
main "$@"