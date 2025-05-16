#!/bin/bash
# =============================================================================
# functions.sh - Shared functions for installation scripts
# =============================================================================

# Installation directory - fixed location
INSTALL_DIR="/tmp/zen5-gentoo-ai"
SCRIPTS_DIR="${INSTALL_DIR}/scripts"
CONFIG_DIR="${INSTALL_DIR}/config"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables (will be set in config.conf)
DISK0=""
DISK1=""
HOSTNAME="io"
USERNAME="eliox"
TIMEZONE="America/Denver"
LOCALE="en_US.UTF-8"
EFI_SIZE="1G"
BOOT_SIZE="1G"
ROOT_SIZE="100G"
SWAP_SIZE="32G"
LUKS_ROOT="crypt_root"
LUKS_TENSOR_A="crypt_tensor_a"
LUKS_TENSOR_B="crypt_tensor_b"
VG_OS="vg_io"
LV_ROOT="lv_io_root"
LV_SWAP="lv_io_swap"
VG_TENSOR="vg_tensor_lab"
LV_TENSOR="lv_tensor_lab"

# Path to temporary configuration
CONFIG_FILE="/tmp/zen5-gentoo-ai.conf"

# === Helper Functions ===

info() {
    echo -e "${GREEN}[+] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[!] Warning: $1${NC}" >&2
}

error() {
    echo -e "${RED}[!] Error: $1${NC}" >&2
}

die() {
    error "$1"
    exit 1
}

verify_root_user() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root"
    fi
}

verify_internet_connection() {
    info "Checking internet connection..."
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        warn "No internet connection detected"
        read -p "Continue anyway? [y/N]: " cont
        if [[ "${cont,,}" != "y" ]]; then
            die "Installation aborted"
        fi
    else
        info "Internet connection confirmed"
    fi
}

verify_live_environment() {
    info "Checking for Gentoo live environment..."
    if [[ ! -f /etc/gentoo-release && ! -f /etc/portage/make.conf ]]; then
        warn "This doesn't appear to be a Gentoo environment"
        read -p "Continue anyway? [y/N]: " cont
        if [[ "${cont,,}" != "y" ]]; then
            die "Installation aborted"
        fi
    else
        info "Gentoo environment confirmed"
    fi
}

confirm_action() {
    local prompt="${1:-Continue with this action?}"
    local default="${2:-n}"
    
    local yn_prompt="[y/N]"
    if [[ "${default,,}" == "y" ]]; then
        yn_prompt="[Y/n]"
    fi
    
    read -p "$prompt $yn_prompt: " response
    response=${response:-$default}
    
    if [[ "${default,,}" == "y" ]]; then
        [[ "${response,,}" != "n" ]]
    else
        [[ "${response,,}" == "y" ]]
    fi
}

check_command() {
    if ! command -v "$1" &>/dev/null; then
        warn "Required command not found: $1"
        if confirm_action "Try to install $1?"; then
            emerge --quiet "$2" || die "Failed to install $2"
        else
            die "Required command $1 not available"
        fi
    fi
}

check_device() {
    if [[ ! -e "$1" ]]; then
        die "Device not found: $1"
    fi
}

create_marker() {
    touch "$1"
    info "Created marker: $1"
}

check_marker() {
    [[ -f "$1" ]]
}

display_main_menu() {
    local config_file="${CONFIG_DIR}/system.conf"
    
    # If config doesn't exist yet, create default
    if [[ ! -f "$config_file" ]]; then
        mkdir -p "${CONFIG_DIR}"
        cat > "$config_file" <<EOF
# System Configuration
HOSTNAME="io"
USERNAME="eliox"
TIMEZONE="America/Denver"
LOCALE="en_US.UTF-8"

# Disk Configuration (will be detected)
DISK0=""
DISK1=""

# Partition Sizes
EFI_SIZE="1G"
BOOT_SIZE="1G"
ROOT_SIZE="100G"
SWAP_SIZE="32G"

# Encryption and LVM names
LUKS_ROOT="crypt_root"
LUKS_TENSOR_A="crypt_tensor_a"
LUKS_TENSOR_B="crypt_tensor_b"
VG_OS="vg_io"
LV_ROOT="lv_io_root"
LV_SWAP="lv_io_swap"
VG_TENSOR="vg_tensor_lab"
LV_TENSOR="lv_tensor_lab"
EOF
    fi
    
    # Edit configuration
    if confirm_action "Would you like to edit the system configuration?"; then
        ${EDITOR:-nano} "$config_file"
    fi
    
    # Source the config
    source "$config_file"
    
    # Detect disks if not set
    if [[ -z "$DISK0" || -z "$DISK1" ]]; then
        info "Detecting available disks..."
        echo
        lsblk -d -o NAME,SIZE,MODEL
        echo
        
        read -p "Enter primary disk device (e.g., nvme0n1): " detected_disk0
        read -p "Enter secondary disk device (e.g., nvme1n1): " detected_disk1
        
        DISK0="/dev/${detected_disk0}"
        DISK1="/dev/${detected_disk1}"
        
        # Save to config
        sed -i "s|^DISK0=.*|DISK0=\"$DISK0\"|" "$config_file"
        sed -i "s|^DISK1=.*|DISK1=\"$DISK1\"|" "$config_file"
        
        info "Disk configuration updated"
    fi
    
    # Show summary
    echo
    echo -e "${BLUE}Configuration Summary:${NC}"
    echo "System hostname: $HOSTNAME"
    echo "Primary disk: $DISK0"
    echo "Secondary disk: $DISK1"
    echo "Username: $USERNAME"
    echo "Timezone: $TIMEZONE"
    echo
    
    if ! confirm_action "Is this configuration correct?"; then
        ${EDITOR:-nano} "$config_file"
        source "$config_file"
    fi
    
    # Save temporary config
    save_temp_config
}

save_temp_config() {
    cat > "$CONFIG_FILE" <<EOF
DISK0="$DISK0"
DISK1="$DISK1"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
TIMEZONE="$TIMEZONE"
LOCALE="$LOCALE"
EFI_SIZE="$EFI_SIZE"
BOOT_SIZE="$BOOT_SIZE"
ROOT_SIZE="$ROOT_SIZE"
SWAP_SIZE="$SWAP_SIZE"
LUKS_ROOT="$LUKS_ROOT"
LUKS_TENSOR_A="$LUKS_TENSOR_A"
LUKS_TENSOR_B="$LUKS_TENSOR_B"
VG_OS="$VG_OS"
LV_ROOT="$LV_ROOT"
LV_SWAP="$LV_SWAP"
VG_TENSOR="$VG_TENSOR"
LV_TENSOR="$LV_TENSOR"
EOF
}

parse_config() {
    # Source the temporary config file
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        die "Configuration file not found"
    fi
}

# Function to run scripts with fixed paths
run_script() {
    local script_name="$1"
    local script_path="${SCRIPTS_DIR}/${script_name}"
    
    if [[ ! -f "${script_path}" ]]; then
        die "Script not found: ${script_path}"
    fi
    
    bash "${script_path}" || die "Script ${script_name} failed"
}

run_preparation_phase() {
    info "Starting preparation phase..."
    
    # Run partition script
    run_script "1-setup-partitions.sh"
    
    # Run encryption script
    run_script "2-setup-encryption.sh"
    
    # Run LVM script
    run_script "3-setup-lvm.sh"
    
    info "Preparation phase completed successfully"
}

run_base_system_phase() {
    info "Starting base system phase..."
    
    # Create filesystems
    run_script "4-create-filesystems.sh"
    
    # Mount all
    run_script "5-mount-all.sh"
    
    # Install base system
    run_script "6-install-base.sh"
    
    # Copy installation files to chroot
    info "Copying installation files to chroot environment..."
    mkdir -p /mnt/gentoo/root/zen5-gentoo-ai
    cp -r "${INSTALL_DIR}"/* /mnt/gentoo/root/zen5-gentoo-ai/
    cp "${CONFIG_FILE}" /mnt/gentoo/root/zen5-gentoo-ai/config/system.conf
    
    info "Base system phase completed successfully"
}

display_chroot_instructions() {
    echo
    echo -e "${BLUE}Chroot Instructions:${NC}"
    echo "Run the following commands to continue installation:"
    echo
    echo "  1. Enter the chroot environment:"
    echo "     chroot /mnt/gentoo /bin/bash"
    echo "     source /etc/profile"
    echo "     export PS1=\"(chroot) \$PS1\""
    echo
    echo "  2. Navigate to the installation directory:"
    echo "     cd /root/zen5-gentoo-ai"
    echo
    echo "  3. Run the chroot installation script:"
    echo "     bash scripts/7-inside-chroot.sh"
    echo
    echo "  4. After completion, exit chroot:"
    echo "     exit"
    echo
    echo "  5. Unmount and reboot:"
    echo "     cd ${INSTALL_DIR} && bash scripts/unmount-and-reboot.sh"
    echo
}

display_post_reboot_instructions() {
    echo
    echo -e "${BLUE}Post-Reboot Instructions:${NC}"
    echo "After rebooting, log in as root and run:"
    echo
    echo "  1. Navigate to the installation directory:"
    echo "     cd /root/zen5-gentoo-ai"
    echo
    echo "  2. Run the post-installation script:"
    echo "     bash scripts/8-post-reboot.sh"
    echo
    echo "This will complete the AI environment setup."
    echo
}