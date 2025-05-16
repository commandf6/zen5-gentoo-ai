#!/bin/bash
# =============================================================================
# 1-setup-partitions.sh - Partition disks
# =============================================================================

set -euo pipefail
trap 'echo "[!] Error on line $LINENO: $BASH_COMMAND"; exit 1' ERR

# Use fixed paths instead of dynamic detection
INSTALL_DIR="/tmp/zen5-gentoo-ai"
SCRIPTS_DIR="${INSTALL_DIR}/scripts"

# Source functions
source "${SCRIPTS_DIR}/functions.sh"

# Configuration
MARKER="/tmp/.01-partitions.done"

main() {
    # Check if already done
    if check_marker "$MARKER"; then
        info "Partitioning already completed. Skipping."
        return 0
    fi

    # Parse configuration
    parse_config

    # Basic checks
    verify_root_user
    check_device "$DISK0"
    check_device "$DISK1"

    info "Starting disk partitioning..."
    
    # Display disk information
    echo
    echo "Target disks:"
    echo "  Primary disk: $DISK0"
    echo "  Secondary disk: $DISK1"
    lsblk "$DISK0" "$DISK1"
    echo

    # Confirm operation - this is destructive!
    echo -e "${RED}WARNING: This will DESTROY all data on $DISK0 and $DISK1${NC}"
    if ! confirm_action "Continue with partitioning?"; then
        die "Partitioning aborted by user"
    fi

    # Check for required tools
    check_command "fdisk" "sys-apps/util-linux"
    
    # Offer interactive or automatic partitioning
    echo
    echo "Partitioning options:"
    echo "1) Interactive partitioning with fdisk"
    echo "2) Automatic partitioning"
    echo
    read -p "Select option [2]: " part_option
    part_option=${part_option:-2}
    
    case "$part_option" in
        1)
            interactive_partitioning
            ;;
        2)
            automatic_partitioning
            ;;
        *)
            die "Invalid option"
            ;;
    esac
    
    # Update partition table
    info "Updating partition tables..."
    partprobe "$DISK0" 2>/dev/null || blockdev --rereadpt "$DISK0" || true
    partprobe "$DISK1" 2>/dev/null || blockdev --rereadpt "$DISK1" || true
    sleep 2

    # Display result
    info "Final partition layout:"
    lsblk -o NAME,SIZE,TYPE,FSTYPE "$DISK0" "$DISK1"

    create_marker "$MARKER"
    info "Partitioning complete"
}

interactive_partitioning() {
    # First disk - 4 partitions (EFI, boot, root, tensor_a)
    info "Partitioning $DISK0 interactively..."
    echo
    echo "Please create the following partitions:"
    echo "  1: EFI System Partition, $EFI_SIZE, type=EFI System (1)"
    echo "  2: Boot partition, $BOOT_SIZE, type=Linux (83)"
    echo "  3: Root partition, $ROOT_SIZE, type=Linux (83)"
    echo "  4: Tensor_A partition, remaining space, type=Linux (83)"
    echo
    echo "Press Enter to continue..."
    read
    fdisk "$DISK0"
    
    # Second disk - 1 partition (tensor_b)
    info "Partitioning $DISK1 interactively..."
    echo
    echo "Please create the following partition:"
    echo "  1: Tensor_B partition, all space, type=Linux (83)"
    echo
    echo "Press Enter to continue..."
    read
    fdisk "$DISK1"
}

automatic_partitioning() {
    # Check for sgdisk
    check_command "sgdisk" "sys-apps/gptfdisk"
    
    # First disk
    info "Partitioning $DISK0 automatically..."
    
    # Wipe existing partition table
    wipefs -a "$DISK0" || true
    sgdisk --zap-all "$DISK0"
    sgdisk -o "$DISK0"  # Create new GPT table

    # Create partitions
    sgdisk -n1:0:+${EFI_SIZE} -t1:EF00 -c1:"EFI System Partition" "$DISK0"
    sgdisk -n2:0:+${BOOT_SIZE} -t2:8300 -c2:"Boot Partition" "$DISK0"
    sgdisk -n3:0:+${ROOT_SIZE} -t3:8300 -c3:"LUKS Root" "$DISK0"
    sgdisk -n4:0:0 -t4:8300 -c4:"LUKS Tensor A" "$DISK0"

    # Second disk
    info "Partitioning $DISK1 automatically..."
    
    # Wipe existing partition table
    wipefs -a "$DISK1" || true
    sgdisk --zap-all "$DISK1"
    sgdisk -o "$DISK1"  # Create new GPT table

    # Create partition
    sgdisk -n1:0:0 -t1:8300 -c1:"LUKS Tensor B" "$DISK1"
}

# Execute main function
main "$@"