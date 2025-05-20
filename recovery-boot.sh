#!/bin/bash
# =============================================================================
# recovery-boot.sh - Recovery script for fixing boot issues
# =============================================================================

set -euo pipefail
trap 'echo "[!] Error on line $LINENO: $BASH_COMMAND"; exit 1' ERR

# Use fixed paths
RECOVERY_DIR="/tmp/zen5-gentoo-recovery"
SOURCE_DIR=$(dirname "$(readlink -f "$0")")
PARENT_DIR=$(dirname "$SOURCE_DIR")

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default paths
MOUNT_ROOT="/mnt/gentoo"

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

# Main function
main() {
    verify_root_user

    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}  Zen5 Gentoo AI System Boot Recovery Tool        ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo
    echo "This script will help you recover a system that fails to boot"
    echo "due to issues with encrypted root filesystem and/or initramfs."
    echo

    # Check necessary tools
    info "Checking for required tools..."
    check_command "cryptsetup" "sys-fs/cryptsetup"
    check_command "lvm" "sys-fs/lvm2"
    check_command "blkid" "sys-apps/util-linux"
    check_command "mount" "sys-apps/util-linux"
    check_command "cp" "sys-apps/coreutils"

    # Detect system disks and encrypted partitions
    detect_system_disks
    
    # Decrypt and mount system
    decrypt_and_mount
    
    # Ask which initramfs generator to use
    select_initramfs_generator
    
    # Set up chroot environment
    setup_chroot
    
    # Show final instructions
    show_final_instructions
}

detect_system_disks() {
    info "Detecting system disks..."
    
    echo
    echo "Available disks:"
    lsblk -o NAME,SIZE,TYPE,FSTYPE
    echo

    # Ask for primary disk
    read -p "Enter primary disk device (e.g., nvme0n1): " primary_disk
    DISK0="/dev/${primary_disk}"
    
    # Try to detect the EFI, boot, and root partitions
    if [[ -e "${DISK0}p1" ]]; then
        EFI_PARTITION="${DISK0}p1"
        BOOT_PARTITION="${DISK0}p2"
        ROOT_PARTITION="${DISK0}p3"
        TENSOR_A_PARTITION="${DISK0}p4"
    elif [[ -e "${DISK0}1" ]]; then
        EFI_PARTITION="${DISK0}1"
        BOOT_PARTITION="${DISK0}2"
        ROOT_PARTITION="${DISK0}3"
        TENSOR_A_PARTITION="${DISK0}4"
    else
        die "Could not detect partitions on ${DISK0}"
    fi
    
    # Verify if this looks like our expected partition layout
    if ! blkid -o value -s TYPE "${EFI_PARTITION}" | grep -q "vfat"; then
        warn "${EFI_PARTITION} is not a vfat partition. Are you sure this is the correct disk?"
        if ! confirm_action "Continue anyway?"; then
            die "Aborting recovery"
        fi
    fi
    
    # Check if ROOT_PARTITION is LUKS encrypted
    if ! cryptsetup isLuks "${ROOT_PARTITION}"; then
        warn "${ROOT_PARTITION} is not a LUKS encrypted partition."
        if ! confirm_action "Continue anyway?"; then
            die "Aborting recovery"
        fi
    fi
    
    # Ask for secondary disk for tensor storage
    read -p "Enter secondary disk device (e.g., nvme1n1) or leave empty to skip: " secondary_disk
    if [[ -n "$secondary_disk" ]]; then
        DISK1="/dev/${secondary_disk}"
        if [[ -e "${DISK1}p1" ]]; then
            TENSOR_B_PARTITION="${DISK1}p1"
        elif [[ -e "${DISK1}1" ]]; then
            TENSOR_B_PARTITION="${DISK1}1"
        else
            warn "Could not detect partitions on ${DISK1}"
            if ! confirm_action "Continue without secondary disk?"; then
                die "Aborting recovery"
            fi
        fi
    fi
    
    info "System disks detected"
    echo "Primary disk: ${DISK0}"
    echo "EFI partition: ${EFI_PARTITION}"
    echo "Boot partition: ${BOOT_PARTITION}"
    echo "Root partition: ${ROOT_PARTITION}"
    if [[ -n "${DISK1:-}" ]]; then
        echo "Secondary disk: ${DISK1}"
    fi
}

decrypt_and_mount() {
    # Get LUKS naming preference
    echo
    echo "LUKS device naming options:"
    echo "1) Use 'cryptroot' (without underscore)"
    echo "2) Use 'crypt_root' (with underscore)"
    read -p "Select naming convention [1]: " luks_naming_option
    luks_naming_option=${luks_naming_option:-1}
    
    if [ "$luks_naming_option" = "1" ]; then
        LUKS_ROOT="cryptroot"
    else
        LUKS_ROOT="crypt_root"
    fi
    
    info "Using LUKS name: ${LUKS_ROOT}"
    
    # Attempt to open the LUKS container
    if ! cryptsetup status "${LUKS_ROOT}" &>/dev/null; then
        info "Opening encrypted root partition..."
        cryptsetup open "${ROOT_PARTITION}" "${LUKS_ROOT}" || die "Failed to open LUKS container"
    else
        info "LUKS container already open: ${LUKS_ROOT}"
    fi
    
    # Detect LVM volume group and logical volumes
    info "Detecting LVM volumes..."
    if ! vgscan --mknodes; then
        die "Failed to scan for volume groups"
    fi
    
    # Activate volume groups
    vgchange -ay
    
    # List available volume groups
    echo
    echo "Available volume groups:"
    vgs
    echo
    
    # Ask for volume group name
    read -p "Enter volume group name [vg_io]: " vg_name
    VG_OS=${vg_name:-vg_io}
    
    # Ask for root logical volume name
    read -p "Enter root logical volume name [lv_io_root]: " lv_name
    LV_ROOT=${lv_name:-lv_io_root}
    
    ROOT_DEVICE="/dev/mapper/${VG_OS}-${LV_ROOT}"
    
    # Check if the root device exists
    if [[ ! -e "${ROOT_DEVICE}" ]]; then
        die "Root device ${ROOT_DEVICE} does not exist"
    fi
    
    # Create mount point
    mkdir -p "${MOUNT_ROOT}"
    
    # Mount root filesystem
    info "Mounting root filesystem..."
    if ! mount -o subvol=@ "${ROOT_DEVICE}" "${MOUNT_ROOT}"; then
        warn "Failed to mount with subvol=@, trying without subvolume..."
        mount "${ROOT_DEVICE}" "${MOUNT_ROOT}" || die "Failed to mount root filesystem"
        
        # Check for btrfs subvolumes
        if btrfs subvolume list "${MOUNT_ROOT}" | grep -q '@'; then
            warn "Btrfs subvolume @ exists but not mounted correctly"
            if confirm_action "Attempt to remount with correct subvolume?"; then
                umount "${MOUNT_ROOT}"
                mount -o subvol=@ "${ROOT_DEVICE}" "${MOUNT_ROOT}" || die "Failed to mount with subvolume"
            fi
        fi
    fi
    
    # Create additional mount points
    mkdir -p "${MOUNT_ROOT}"/{boot,boot/efi,home,.snapshots,tensor_lab}
    
    # Mount boot and EFI partitions
    info "Mounting boot partitions..."
    mount "${BOOT_PARTITION}" "${MOUNT_ROOT}/boot" || warn "Failed to mount boot partition (non-fatal)"
    mount "${EFI_PARTITION}" "${MOUNT_ROOT}/boot/efi" || warn "Failed to mount EFI partition (non-fatal)"
    
    # Mount btrfs subvolumes
    info "Mounting Btrfs subvolumes..."
    mount -o subvol=@home "${ROOT_DEVICE}" "${MOUNT_ROOT}/home" || warn "Failed to mount home subvolume (non-fatal)"
    mount -o subvol=@snapshots "${ROOT_DEVICE}" "${MOUNT_ROOT}/.snapshots" || warn "Failed to mount snapshots subvolume (non-fatal)"
    
    # Mount pseudo-filesystems
    info "Mounting pseudo-filesystems..."
    mount --types proc /proc "${MOUNT_ROOT}/proc"
    mount --rbind /sys "${MOUNT_ROOT}/sys"
    mount --make-rslave "${MOUNT_ROOT}/sys"
    mount --rbind /dev "${MOUNT_ROOT}/dev"
    mount --make-rslave "${MOUNT_ROOT}/dev"
    mount --bind /run "${MOUNT_ROOT}/run" || true
    
    # Display mount status
    info "Current mount status:"
    findmnt -R "${MOUNT_ROOT}" || mount | grep "${MOUNT_ROOT}"
}

select_initramfs_generator() {
    # Choose initramfs generator
    echo
    echo "Initramfs generator options:"
    echo "1) Dracut (modern, modular approach)"
    echo "2) Genkernel (traditional Gentoo approach)"
    echo
    read -p "Select initramfs generator [1]: " initramfs_option
    INITRAMFS_OPTION=${initramfs_option:-1}
    
    # Set LUKS_NAME to be used in the bootloader configuration
    LUKS_NAME="${LUKS_ROOT}"
    
    # Create the recovery chroot script
    info "Creating recovery chroot script..."
    cat > "${MOUNT_ROOT}/root/recovery-chroot.sh" <<EOF
#!/bin/bash
# Recovery operations inside chroot

set -euo pipefail
echo "[+] Starting recovery operations inside chroot..."

# Update environment
env-update && source /etc/profile
export PS1="(chroot) \$PS1"

# Verify kernel and firmware packages
echo "[+] Verifying kernel packages..."
if ! ls -l /usr/src/linux; then
    echo "[-] Kernel sources not found. Installing..."
    emerge --ask sys-kernel/gentoo-sources sys-kernel/linux-firmware
    eselect kernel list
    read -p "Select kernel to use (number): " kernel_num
    eselect kernel set "\$kernel_num"
fi

# Install the chosen initramfs generator
if [ "${INITRAMFS_OPTION}" = "1" ]; then
    echo "[+] Installing and configuring Dracut..."
    emerge --ask sys-kernel/dracut
    
    # Configure dracut
    mkdir -p /etc/dracut.conf.d
    cat > /etc/dracut.conf.d/encryption.conf <<DRACUT_EOF
add_dracutmodules+=" crypt dm rootfs-block lvm btrfs "
omit_dracutmodules+=" plymouth "

add_drivers+=" nvme btrfs dm_crypt dm_mod "

filesystems+=" btrfs ext4 vfat "

rd_luks="yes"
rd_luks_allow_discards="yes"

compress="zstd"
hostonly="yes"
hostonly_cmdline="yes"

show_modules="yes"
early_microcode="yes"
DRACUT_EOF

    # Get latest kernel version
    KVER=\$(ls -1 /lib/modules | sort | tail -1)
    
    # Generate initramfs with dracut
    echo "[+] Generating initramfs with dracut for kernel \$KVER..."
    dracut --force --kver "\$KVER" || echo "[-] Dracut initramfs creation failed"
    
    # Configure GRUB for dracut
    cat > /etc/default/grub <<GRUB_EOF
GRUB_DISTRIBUTOR="Gentoo"
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX="rd.luks.uuid=\$(blkid -s UUID -o value ${ROOT_PARTITION}) rd.luks.name=\$(blkid -s UUID -o value ${ROOT_PARTITION})=${LUKS_NAME} root=/dev/mapper/${VG_OS}-${LV_ROOT} rootfstype=btrfs rootflags=subvol=@ dolvm"
GRUB_ENABLE_CRYPTODISK=y
GRUB_DISABLE_OS_PROBER=false
GRUB_EOF

else
    echo "[+] Installing and configuring Genkernel..."
    emerge --ask sys-kernel/genkernel
    
    # Generate initramfs with genkernel
    echo "[+] Generating initramfs with genkernel..."
    genkernel --install --luks --lvm --btrfs initramfs || echo "[-] Genkernel initramfs creation failed"
    
    # Configure GRUB for genkernel
    cat > /etc/default/grub <<GRUB_EOF
GRUB_DISTRIBUTOR="Gentoo"
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX="dolvm ${LUKS_NAME}=UUID=\$(blkid -s UUID -o value ${ROOT_PARTITION}) root=/dev/mapper/${VG_OS}-${LV_ROOT} rootfstype=btrfs rootflags=subvol=@"
GRUB_ENABLE_CRYPTODISK=y
GRUB_DISABLE_OS_PROBER=false
GRUB_EOF
fi

# Create/update crypttab
echo "[+] Updating crypttab with selected naming convention..."
cat > /etc/crypttab <<CRYPTTAB_EOF
${LUKS_NAME}     UUID=\$(blkid -s UUID -o value ${ROOT_PARTITION})    none luks,discard,tries=3
CRYPTTAB_EOF

# Reinstall GRUB
echo "[+] Reinstalling GRUB bootloader..."
emerge --ask sys-boot/grub:2 sys-boot/efibootmgr || echo "[-] Failed to install bootloader packages"

# Install GRUB to EFI
echo "[+] Installing GRUB to EFI system partition..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Gentoo" --recheck || echo "[-] GRUB installation failed"

# Generate GRUB config
echo "[+] Generating GRUB configuration..."
grub-mkconfig -o /boot/grub/grub.cfg || echo "[-] GRUB config generation failed"

echo "[+] Recovery operations completed!"
echo "You can now exit the chroot and reboot to test if the system boots correctly."
EOF
    
    # Make the script executable
    chmod +x "${MOUNT_ROOT}/root/recovery-chroot.sh"
}

setup_chroot() {
    # Copy resolv.conf for network access in chroot
    cp /etc/resolv.conf "${MOUNT_ROOT}/etc/resolv.conf"
    
    info "Chroot environment is ready."
    echo
    echo "To complete the recovery process:"
    echo "1. Enter the chroot environment:"
    echo "   chroot ${MOUNT_ROOT} /bin/bash"
    echo "   source /etc/profile"
    echo "   export PS1=\"(chroot) \$PS1\""
    echo
    echo "2. Run the recovery script:"
    echo "   bash /root/recovery-chroot.sh"
    echo
    echo "3. After completion, exit chroot:"
    echo "   exit"
    echo
    
    if confirm_action "Would you like to enter the chroot environment now?"; then
        info "Entering chroot environment..."
        chroot "${MOUNT_ROOT}" /bin/bash
    fi
}

show_final_instructions() {
    echo
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}  Recovery Process Complete                       ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo
    echo "If you have completed the chroot operations, you can now:"
    echo "1. Exit the chroot environment (if you're still in it)"
    echo "2. Unmount all filesystems:"
    echo "   umount -R ${MOUNT_ROOT}"
    echo "3. Close the LUKS container:"
    echo "   cryptsetup close ${LUKS_ROOT}"
    echo "4. Reboot the system to test if it boots correctly:"
    echo "   reboot"
    echo
}

# Execute main function
main "$@"