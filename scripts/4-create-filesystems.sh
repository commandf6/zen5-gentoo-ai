#!/bin/bash
# =============================================================================
# 4-create-filesystems.sh - Format filesystems and create Btrfs subvolumes
# =============================================================================

set -euo pipefail
trap 'echo "[!] Error on line $LINENO: $BASH_COMMAND"; exit 1' ERR

# Use fixed paths instead of dynamic detection
INSTALL_DIR="/tmp/zen5-gentoo-ai"
SCRIPTS_DIR="${INSTALL_DIR}/scripts"

# Source functions
source "${SCRIPTS_DIR}/functions.sh"

# Configuration
MARKER="/tmp/.04-filesystems.done"

main() {
    # Check if already done
    if check_marker "$MARKER"; then
        info "Filesystems already created. Skipping."
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

    # Check for filesystem creation tools
    check_command "mkfs.vfat" "sys-fs/dosfstools"
    check_command "mkfs.ext4" "sys-fs/e2fsprogs"
    check_command "mkfs.btrfs" "sys-fs/btrfs-progs"
    check_command "mkswap" "sys-apps/util-linux"

    info "Creating filesystems..."

    # Format EFI partition
    info "Formatting EFI partition (${EFI_PARTITION})..."
    if ! confirm_action "Format EFI partition?"; then
        die "Filesystem creation aborted by user"
    fi
    mkfs.vfat -F 32 -n EFI "$EFI_PARTITION" || die "Failed to format EFI partition"

    # Format boot partition
    info "Formatting boot partition (${BOOT_PARTITION})..."
    if ! confirm_action "Format boot partition?"; then
        die "Filesystem creation aborted by user"
    fi
    mkfs.ext4 -L BOOT "$BOOT_PARTITION" || die "Failed to format boot partition"

    # Format root filesystem
    info "Formatting root filesystem with Btrfs (${ROOT_DEVICE})..."
    if ! confirm_action "Format root filesystem?"; then
        die "Filesystem creation aborted by user"
    fi
    mkfs.btrfs -f -L ROOT "$ROOT_DEVICE" || die "Failed to format root filesystem"

    # Create Btrfs subvolumes
    info "Creating Btrfs subvolumes for root..."
    TEMP_MOUNT="/mnt/btrfs-root"
    mkdir -p "$TEMP_MOUNT"
    mount "$ROOT_DEVICE" "$TEMP_MOUNT" || die "Failed to mount root for subvolume creation"

    # Create subvolumes
    btrfs subvolume create "$TEMP_MOUNT/@" || die "Failed to create @ subvolume"
    btrfs subvolume create "$TEMP_MOUNT/@home" || die "Failed to create @home subvolume"
    btrfs subvolume create "$TEMP_MOUNT/@snapshots" || die "Failed to create @snapshots subvolume"

    # Set default subvolume
    btrfs subvolume list "$TEMP_MOUNT"
    SUBVOL_ID=$(btrfs subvolume list "$TEMP_MOUNT" | grep -E '@$' | awk '{print $2}')
    btrfs subvolume set-default "$SUBVOL_ID" "$TEMP_MOUNT" || die "Failed to set default subvolume"

    # Unmount temporary mount
    umount "$TEMP_MOUNT"
    rmdir "$TEMP_MOUNT"

    # Format swap
    info "Formatting swap partition (${SWAP_DEVICE})..."
    if ! confirm_action "Format swap partition?"; then
        die "Swap formatting aborted by user"
    fi
    mkswap -L SWAP "$SWAP_DEVICE" || die "Failed to format swap"

    # Format tensor filesystem
    info "Formatting tensor filesystem with Btrfs (${TENSOR_DEVICE})..."
    if ! confirm_action "Format tensor filesystem?"; then
        die "Tensor filesystem formatting aborted by user"
    fi
    mkfs.btrfs -f -L TENSOR_LAB "$TENSOR_DEVICE" || die "Failed to format tensor filesystem"

    # Display results
    info "Filesystem formatting complete:"
    lsblk -f "$DISK0" "$DISK1"

    create_marker "$MARKER"
    info "Filesystem creation complete"
}

# Execute main function
main "$@"