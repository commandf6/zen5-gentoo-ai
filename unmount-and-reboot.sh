#!/bin/bash
# =============================================================================
# umount-and-reboot.sh - Safely unmount and reboot the system
# =============================================================================

set -euo pipefail
trap 'echo "[!] Error on line $LINENO: $BASH_COMMAND"; exit 1' ERR

# Script directory detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Source functions
source "$SCRIPT_DIR/scripts/functions.sh"

# Configuration
verify_root_user

# Parse configuration
if [[ -f "/tmp/zen5-gentoo-ai.conf" ]]; then
    source "/tmp/zen5-gentoo-ai.conf"
else
    LUKS_ROOT="crypt_root"
    LUKS_TENSOR_A="crypt_tensor_a"
    LUKS_TENSOR_B="crypt_tensor_b"
fi

info "Preparing to unmount filesystems and reboot..."

# Confirm operation
if ! confirm_action "Unmount all filesystems and reboot?"; then
    echo "Operation cancelled. You can manually unmount with:"
    echo "  cd / && umount -R /mnt/gentoo && reboot"
    exit 0
fi

# Unmount all filesystems
info "Unmounting all filesystems..."
cd /
umount -R /mnt/gentoo || warn "Some filesystems could not be unmounted."

# Close encrypted volumes
info "Closing encrypted volumes..."
cryptsetup close "$LUKS_ROOT" || warn "Failed to close $LUKS_ROOT"
cryptsetup close "$LUKS_TENSOR_A" || warn "Failed to close $LUKS_TENSOR_A"
cryptsetup close "$LUKS_TENSOR_B" || warn "Failed to close $LUKS_TENSOR_B"

info "All filesystems unmounted and encrypted volumes closed."

# Confirm reboot
if confirm_action "Ready to reboot. Continue?"; then
    info "Rebooting system..."
    reboot
else
    info "Reboot cancelled. System is ready to be powered off."
fi