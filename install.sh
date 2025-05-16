
#!/bin/bash
# =============================================================================
# install.sh - Main installation script
# =============================================================================

set -euo pipefail
trap 'echo "[!] Error on line $LINENO: $BASH_COMMAND"; exit 1' ERR

# Installation directory - fixed location
INSTALL_DIR="/tmp/zen5-gentoo-ai"
SCRIPTS_DIR="${INSTALL_DIR}/scripts"

# Ensure we're in the right directory
if [[ ! -d "${INSTALL_DIR}" ]]; then
    echo "Creating installation directory at ${INSTALL_DIR}"
    mkdir -p "${INSTALL_DIR}"
    # If this is the first run and directory was just created,
    # the user should copy all files to this location
    echo "Please copy all installation files to ${INSTALL_DIR}"
    echo "Then run this script again."
    exit 1
fi

# Change to the installation directory
cd "${INSTALL_DIR}"

# Source functions
if [[ ! -f "${SCRIPTS_DIR}/functions.sh" ]]; then
    echo "Error: functions.sh not found in ${SCRIPTS_DIR}"
    echo "Please ensure all installation files are in ${INSTALL_DIR}"
    exit 1
fi

source "${SCRIPTS_DIR}/functions.sh"

# Welcome message
clear
echo -e "${GREEN}=======================================================${NC}"
echo -e "${GREEN}           Zen5 Gentoo AI Installation System           ${NC}"
echo -e "${GREEN}=======================================================${NC}"
echo
echo "This script will install Gentoo Linux optimized for:"
echo "  - AMD Zen 5 processors"
echo "  - NVIDIA GPUs with CUDA"
echo "  - AI/ML workloads"
echo "  - Full disk encryption with LUKS2"
echo "  - Btrfs with subvolumes"
echo "  - Mirrored storage for AI data"
echo
echo -e "${YELLOW}WARNING: This will destroy all data on selected disks!${NC}"
echo

# Verify environment
verify_root_user
verify_internet_connection
verify_live_environment

# Display main menu
display_main_menu

# Parse configuration
parse_config

# Phase selection menu
while true; do
    cat <<EOF

${GREEN}Installation Phases:${NC}
1) Preparation (partitioning, encryption, LVM)
2) Base System (filesystems, stage3, chroot setup)
3) System Configuration (inside chroot) - Manual step
4) Post-Install Verification
5) All phases (1-2 automatically, guide through 3-4)
q) Quit

EOF
    read -p "Select phase to execute [5]: " phase
    phase=${phase:-5}
    
    case "$phase" in
        1)
            "${SCRIPTS_DIR}/1-setup-partitions.sh"
            ;;
        2)
            "${SCRIPTS_DIR}/2-setup-encryption.sh"
            "${SCRIPTS_DIR}/3-setup-lvm.sh"
            "${SCRIPTS_DIR}/4-create-filesystems.sh"
            "${SCRIPTS_DIR}/5-mount-all.sh"
            "${SCRIPTS_DIR}/6-install-base.sh"
            ;;
        3)
            echo -e "${YELLOW}Phase 3 requires manual chroot. Instructions:${NC}"
            display_chroot_instructions
            ;;
        4)
            echo -e "${YELLOW}Phase 4 is post-reboot. Instructions:${NC}"
            display_post_reboot_instructions
            ;;
        5)
            "${SCRIPTS_DIR}/1-setup-partitions.sh"
            "${SCRIPTS_DIR}/2-setup-encryption.sh"
            "${SCRIPTS_DIR}/3-setup-lvm.sh"
            "${SCRIPTS_DIR}/4-create-filesystems.sh"
            "${SCRIPTS_DIR}/5-mount-all.sh"
            "${SCRIPTS_DIR}/6-install-base.sh"
            echo
            echo -e "${GREEN}Base installation completed successfully!${NC}"
            echo
            display_chroot_instructions
            ;;
        q|Q)
            echo "Exiting installation."
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid selection.${NC}"
            ;;
    esac
done

# This point should not be reached
exit 0