#!/bin/bash
# =============================================================================
# 2-setup-encryption.sh - Set up LUKS encryption for partitions
# =============================================================================

set -euo pipefail
trap 'echo "[!] Error on line $LINENO: $BASH_COMMAND"; exit 1' ERR

# Use fixed paths instead of dynamic detection
INSTALL_DIR="/tmp/zen5-gentoo-ai"
SCRIPTS_DIR="${INSTALL_DIR}/scripts"

# Source functions
source "${SCRIPTS_DIR}/functions.sh"

# Configuration
MARKER="/tmp/.02-encryption.done"

main() {
    # Check if already done
    if check_marker "$MARKER"; then
        info "Encryption already set up. Skipping."
        return 0
    fi

    # Parse configuration
    parse_config

    # Define partitions based on config
    ROOT_PARTITION="${DISK0}p3"
    TENSOR_A_PARTITION="${DISK0}p4"
    TENSOR_B_PARTITION="${DISK1}p1"

    # Basic checks
    verify_root_user
    check_device "$ROOT_PARTITION"
    check_device "$TENSOR_A_PARTITION"
    check_device "$TENSOR_B_PARTITION"

    # Check for cryptsetup
    check_command "cryptsetup" "sys-fs/cryptsetup"

    info "Setting up LUKS encryption..."
    echo
    echo "You will be prompted for a passphrase for each volume."
    echo "Use a strong passphrase you won't forget!"
    echo "You can use the same passphrase for all volumes or different ones."
    echo

    # Encrypt root partition
    info "Encrypting root partition ($ROOT_PARTITION)..."
    if ! confirm_action "Continue with encrypting root partition?"; then
        die "Encryption aborted by user"
    fi
    
    cryptsetup luksFormat --type luks2 \
        --cipher aes-xts-plain64 \
        --key-size 512 \
        --hash sha512 \
        --pbkdf argon2id \
        --use-random \
        "$ROOT_PARTITION"

    # Open root partition
    info "Opening root partition..."
    cryptsetup open "$ROOT_PARTITION" "$LUKS_ROOT"

    # Encrypt tensor_a partition
    info "Encrypting tensor_a partition ($TENSOR_A_PARTITION)..."
    if ! confirm_action "Continue with encrypting tensor_a partition?"; then
        cryptsetup close "$LUKS_ROOT"
        die "Encryption aborted by user"
    fi
    
    cryptsetup luksFormat --type luks2 \
        --cipher aes-xts-plain64 \
        --key-size 512 \
        --hash sha512 \
        --pbkdf argon2id \
        --use-random \
        "$TENSOR_A_PARTITION"

    # Open tensor_a partition
    info "Opening tensor_a partition..."
    cryptsetup open "$TENSOR_A_PARTITION" "$LUKS_TENSOR_A"

    # Encrypt tensor_b partition
    info "Encrypting tensor_b partition ($TENSOR_B_PARTITION)..."
    if ! confirm_action "Continue with encrypting tensor_b partition?"; then
        cryptsetup close "$LUKS_ROOT"
        cryptsetup close "$LUKS_TENSOR_A"
        die "Encryption aborted by user"
    fi
    
    cryptsetup luksFormat --type luks2 \
        --cipher aes-xts-plain64 \
        --key-size 512 \
        --hash sha512 \
        --pbkdf argon2id \
        --use-random \
        "$TENSOR_B_PARTITION"

    # Open tensor_b partition
    info "Opening tensor_b partition..."
    cryptsetup open "$TENSOR_B_PARTITION" "$LUKS_TENSOR_B"

    # Verify all devices are open
    info "Verifying encrypted volumes..."
    for device in "$LUKS_ROOT" "$LUKS_TENSOR_A" "$LUKS_TENSOR_B"; do
        if [[ ! -e "/dev/mapper/$device" ]]; then
            die "Failed to open encrypted volume: /dev/mapper/$device"
        fi
        echo "  ✓ /dev/mapper/$device is available"
    done

    # Display status
    info "LUKS encryption status:"
    for device in "$LUKS_ROOT" "$LUKS_TENSOR_A" "$LUKS_TENSOR_B"; do
        cryptsetup status "$device"
        echo
    done

    create_marker "$MARKER"
    info "LUKS encryption setup complete"
}

# Execute main function
main "$@"