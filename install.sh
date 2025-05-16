#!/bin/bash
# =============================================================================
# install.sh - Main installation script
# =============================================================================

set -euo pipefail
trap 'echo "[!] Error on line $LINENO: $BASH_COMMAND"; exit 1' ERR

# Detect script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source functions
source "$SCRIPT_DIR/scripts/functions.sh"

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
            run_preparation_phase
            ;;
        2)
            run_base_system_phase
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
            run_preparation_phase
            run_base_system_phase
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