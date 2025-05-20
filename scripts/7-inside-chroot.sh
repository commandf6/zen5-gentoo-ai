#!/bin/bash
# =============================================================================
# 7-inside-chroot.sh - Inside chroot configuration
# =============================================================================

set -euo pipefail
trap 'echo "[!] Error on line $LINENO: $BASH_COMMAND"; exit 1' ERR

# Use fixed paths instead of dynamic detection
# Note: Inside chroot, our install path is different
INSTALL_DIR="/root/zen5-gentoo-ai"
SCRIPTS_DIR="${INSTALL_DIR}/scripts"

# Source functions
source "${SCRIPTS_DIR}/functions.sh"

# Configuration
MARKER="/tmp/.07-chroot.done"

main() {
    # Check if already done
    if check_marker "$MARKER"; then
        info "Chroot configuration already completed. Skipping."
        return 0
    fi

    # Parse configuration
    parse_config

    # Check if inside chroot
    if ! is_inside_chroot; then
        die "This script must be run inside the chroot environment"
    fi

    info "Configuring system inside chroot..."

    # Update environment
    env-update && source /etc/profile
    export PS1="(chroot) $PS1"

    # Set hostname
    info "Setting hostname to $HOSTNAME..."
    echo "$HOSTNAME" > /etc/hostname

    # Set timezone
    info "Setting timezone to $TIMEZONE..."
    echo "$TIMEZONE" > /etc/timezone
    emerge --config sys-libs/timezone-data

    # Set locales
    info "Configuring locales..."
    echo "${LOCALE} UTF-8" > /etc/locale.gen
    locale-gen
    eselect locale set "${LOCALE%.*}.utf8"
    env-update && source /etc/profile

    # Sync portage
    info "Syncing Portage tree..."
    emerge-webrsync
    
    # Set profile
    info "Setting Gentoo profile..."
    eselect profile list
    read -p "Enter profile number to select (default desktop): " profile_num
    if [[ -n "$profile_num" ]]; then
        eselect profile set "$profile_num"
    else
        eselect profile set default/linux/amd64/17.1/desktop
    fi
    
    # Detect CPU flags
    info "Detecting CPU flags..."
    emerge -1 app-portage/cpuid2cpuflags
    CPU_FLAGS_DETECTED=$(cpuid2cpuflags | sed 's/CPU_FLAGS_X86: //')
    echo "# CPU flags detected by cpuid2cpuflags" >> /etc/portage/make.conf
    echo "CPU_FLAGS_X86=\"${CPU_FLAGS_DETECTED}\"" >> /etc/portage/make.conf

    # Update @world set
    info "Updating @world set..."
    emerge --ask --verbose --update --deep --newuse @world || warn "World update failed (non-fatal)"

    # Install essential tools
    info "Installing essential tools..."
    emerge --ask app-portage/gentoolkit app-portage/eix sys-apps/mlocate || warn "Failed to install some tools (non-fatal)"

    # Create fstab
    info "Configuring /etc/fstab..."
    create_fstab

    # Install and configure kernel
    info "Installing kernel..."
    install_kernel

    # Install and configure bootloader
    info "Installing bootloader..."
    install_bootloader

    # Configure networking
    info "Setting up networking..."
    setup_networking

    # Create user account
    info "Creating user account..."
    create_user

    # Set root password
    info "Setting root password..."
    echo "Please enter a password for the root user:"
    passwd

    # Update EIX database
    eix-update || true

    create_marker "$MARKER"
    info "Chroot configuration complete"
    
    echo
    echo "Exit the chroot environment with 'exit', then run the following:"
    echo "cd /tmp/zen5-gentoo-ai && bash scripts/unmount-and-reboot.sh"
}

is_inside_chroot() {
    # Check if we're in a chroot environment
    [[ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/.)" ]]
}

create_fstab() {
    # Get device UUIDs
    local efi_uuid=$(blkid -s UUID -o value "${DISK0}p1")
    local boot_uuid=$(blkid -s UUID -o value "${DISK0}p2")
    local root_uuid=$(blkid -s UUID -o value "/dev/mapper/${VG_OS}-${LV_ROOT}")
    local swap_uuid=$(blkid -s UUID -o value "/dev/mapper/${VG_OS}-${LV_SWAP}")
    local tensor_uuid=$(blkid -s UUID -o value "/dev/mapper/${VG_TENSOR}-${LV_TENSOR}")

    # Create fstab file
    cat > /etc/fstab <<EOF
# <filesystem>                             <mountpoint>    <type>       <options>                         <dump> <pass>
UUID=${efi_uuid}                          /boot/efi       vfat         defaults                           0      2
UUID=${boot_uuid}                         /boot           ext4         defaults                           0      2
UUID=${root_uuid}                         /               btrfs        defaults,subvol=@                  0      1
UUID=${root_uuid}                         /home           btrfs        defaults,subvol=@home              0      2
UUID=${root_uuid}                         /.snapshots     btrfs        defaults,subvol=@snapshots         0      2
UUID=${swap_uuid}                         none            swap         sw                                 0      0
UUID=${tensor_uuid}                       /tensor_lab     btrfs        defaults                           0      2

# Temporary filesystems
tmpfs                                     /tmp            tmpfs        defaults,nosuid,nodev,size=8G      0      0
EOF

    info "fstab configuration complete"
}

install_kernel() {
    # Install kernel sources and tools
    info "Installing kernel sources and tools..."
    emerge --ask sys-kernel/gentoo-sources sys-kernel/linux-firmware || die "Failed to install kernel packages"

    # Setup kernel symlink
    eselect kernel list
    read -p "Select kernel to use (number): " kernel_num
    eselect kernel set "$kernel_num"

    # Configure kernel options
    cd /usr/src/linux
    
    echo
    echo "Kernel configuration options:"
    echo "1) Use menuconfig to configure manually"
    echo "2) Use genkernel to configure and build automatically"
    echo "3) Use Zen5 AI-optimized kernel config (recommended)"
    echo "4) Use distribution config (if available)"
    echo
    read -p "Select option [3]: " kernel_config_option
    kernel_config_option=${kernel_config_option:-3}
    
    case "$kernel_config_option" in
        1)
            make menuconfig
            ;;
        2)
            emerge --ask sys-kernel/genkernel
            genkernel --menuconfig all
            ;;
        3)
            info "Using provided Zen5 AI-optimized kernel config..."
            cp ${INSTALL_DIR}/config/kernel.config .config
            make olddefconfig
            ;;
        4)
            if [[ -f "/proc/config.gz" ]]; then
                zcat /proc/config.gz > .config
                make olddefconfig
            else
                warn "No distribution config found, using default config"
                make defconfig
                make menuconfig
            fi
            ;;
        *)
            die "Invalid option"
            ;;
    esac
    
    # Choose initramfs generator
    echo
    echo "Initramfs generator options:"
    echo "1) Dracut (modern, modular approach)"
    echo "2) Genkernel (traditional Gentoo approach)"
    echo
    read -p "Select initramfs generator [1]: " initramfs_option
    initramfs_option=${initramfs_option:-1}
    
    # Install selected initramfs generator
    case "$initramfs_option" in
        1)
            info "Installing and configuring Dracut..."
            emerge --ask sys-kernel/dracut || die "Failed to install dracut"
            use_dracut=true
            ;;
        2)
            info "Installing and configuring Genkernel..."
            emerge --ask sys-kernel/genkernel || die "Failed to install genkernel"
            use_dracut=false
            ;;
        *)
            die "Invalid option"
            ;;
    esac
    
    # Decide on LUKS naming convention (crucial for boot success)
    if [ "$use_dracut" = true ]; then
        # For dracut, recommend without underscore for better compatibility
        echo
        echo "LUKS naming convention for Dracut:"
        echo "1) Use 'cryptroot' (without underscore, recommended for dracut)"
        echo "2) Use 'crypt_root' (with underscore, current setting)"
        echo
        read -p "Select LUKS naming convention [1]: " luks_naming_option
        luks_naming_option=${luks_naming_option:-1}
        
        if [ "$luks_naming_option" = "1" ]; then
            # Update to name without underscore
            NEW_LUKS_ROOT="cryptroot"
            info "Switching to 'cryptroot' naming convention"
        else
            # Keep current naming
            NEW_LUKS_ROOT="${LUKS_ROOT}"
            info "Keeping '${LUKS_ROOT}' naming convention"
        fi
    else
        # For genkernel, use with underscore for better compatibility
        echo
        echo "LUKS naming convention for Genkernel:"
        echo "1) Use 'crypt_root' (with underscore, recommended for genkernel)"
        echo "2) Use 'cryptroot' (without underscore)"
        echo
        read -p "Select LUKS naming convention [1]: " luks_naming_option
        luks_naming_option=${luks_naming_option:-1}
        
        if [ "$luks_naming_option" = "1" ]; then
            # Use name with underscore
            NEW_LUKS_ROOT="crypt_root"
            info "Using 'crypt_root' naming convention"
        else
            # Use name without underscore
            NEW_LUKS_ROOT="cryptroot"
            info "Using 'cryptroot' naming convention"
        fi
    fi
    
    # Update crypttab with the selected naming convention
    info "Updating crypttab with selected naming convention..."
    cat > /etc/crypttab <<EOF
${NEW_LUKS_ROOT}     UUID=$(blkid -s UUID -o value ${DISK0}p3)    none luks,discard,tries=3
${LUKS_TENSOR_A} UUID=$(blkid -s UUID -o value ${DISK0}p4)    none luks,discard,tries=1,nofail
${LUKS_TENSOR_B} UUID=$(blkid -s UUID -o value ${DISK1}p1)    none luks,discard,tries=1,nofail
EOF
    
    # Build kernel if not using genkernel
    if [ "$use_dracut" = true ] || [ "$kernel_config_option" != "2" ]; then
        info "Building kernel..."
        make -j$(nproc) || die "Kernel build failed"
        make modules_install || die "Module installation failed"
        make install || die "Kernel installation failed"
    fi
    
    # Get kernel version
    KVER=$(make kernelrelease)
    
    # Generate initramfs based on selected tool
    if [ "$use_dracut" = true ]; then
        # Configure dracut
        info "Configuring dracut for initramfs generation..."
        mkdir -p /etc/dracut.conf.d
        cat > /etc/dracut.conf.d/encryption.conf <<EOF
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
EOF

        # Generate initramfs with dracut
        info "Generating initramfs with dracut..."
        dracut --force --kver "$KVER" || die "Dracut initramfs creation failed"
        
        # Store the dracut command for future reference
        echo "dracut --force --kver $KVER" > /root/last_initramfs_command.txt
        
    else
        # Configure genkernel for our specific needs
        info "Generating initramfs with genkernel..."
        if [ "$kernel_config_option" = "3" ]; then
            # Use existing kernel configuration with genkernel
            genkernel --install --luks --lvm --btrfs --no-menuconfig --kernel-config=/usr/src/linux/.config initramfs || die "Genkernel initramfs creation failed"
        else
            # Let genkernel handle everything
            genkernel --install --luks --lvm --btrfs all || die "Genkernel full build failed"
        fi
        
        # Store the genkernel command for future reference
        if [ "$kernel_config_option" = "3" ]; then
            echo "genkernel --install --luks --lvm --btrfs --no-menuconfig --kernel-config=/usr/src/linux/.config initramfs" > /root/last_initramfs_command.txt
        else
            echo "genkernel --install --luks --lvm --btrfs all" > /root/last_initramfs_command.txt
        fi
    fi
    
    # Store the selected initramfs generator and naming for future reference
    echo "INITRAMFS_GENERATOR=$initramfs_option" > /root/boot_config.txt
    echo "LUKS_NAME=${NEW_LUKS_ROOT}" >> /root/boot_config.txt
    
    info "Kernel and initramfs built successfully"
}

install_bootloader() {
    # Install GRUB and efibootmgr
    info "Installing GRUB bootloader..."
    emerge --ask sys-boot/grub:2 sys-boot/efibootmgr || die "Failed to install bootloader packages"
    
    # Load saved boot configuration if exists
    if [[ -f "/root/boot_config.txt" ]]; then
        source /root/boot_config.txt
    else
        # Default values if not found
        INITRAMFS_GENERATOR=1  # Default to dracut
        LUKS_NAME="${LUKS_ROOT}"
    fi
    
    # Configure GRUB for LUKS based on the selected initramfs generator
    info "Configuring GRUB for encrypted boot..."
    
    if [ "$INITRAMFS_GENERATOR" = "1" ]; then
        # Dracut-specific GRUB configuration
        cat > /etc/default/grub <<EOF
GRUB_DISTRIBUTOR="Gentoo"
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX="rd.luks.uuid=$(blkid -s UUID -o value ${DISK0}p3) rd.luks.name=$(blkid -s UUID -o value ${DISK0}p3)=${LUKS_NAME} root=/dev/mapper/${VG_OS}-${LV_ROOT} rootfstype=btrfs rootflags=subvol=@ dolvm"
GRUB_ENABLE_CRYPTODISK=y
GRUB_DISABLE_OS_PROBER=false
EOF
    else
        # Genkernel-specific GRUB configuration
        cat > /etc/default/grub <<EOF
GRUB_DISTRIBUTOR="Gentoo"
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX="dolvm ${LUKS_NAME}=UUID=$(blkid -s UUID -o value ${DISK0}p3) root=/dev/mapper/${VG_OS}-${LV_ROOT} rootfstype=btrfs rootflags=subvol=@"
GRUB_ENABLE_CRYPTODISK=y
GRUB_DISABLE_OS_PROBER=false
EOF
    fi

    # Install GRUB to EFI
    info "Installing GRUB to EFI system partition..."
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Gentoo" --recheck || die "GRUB installation failed"
    
    # Generate GRUB config
    info "Generating GRUB configuration..."
    grub-mkconfig -o /boot/grub/grub.cfg || die "GRUB config generation failed"
    
    info "Bootloader installation complete"
}

setup_networking() {
    # Install NetworkManager
    info "Installing and configuring NetworkManager..."
    emerge --ask net-misc/networkmanager || die "Failed to install NetworkManager"
    
    # Configure hosts file
    cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

    # Add NetworkManager to default runlevel
    rc-update add NetworkManager default
    
    info "Networking configuration complete"
}

create_user() {
    # Install sudo
    info "Installing sudo..."
    emerge --ask app-admin/sudo || die "Failed to install sudo"
    
    # Create sudo config
    mkdir -p /etc/sudoers.d
    echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
    chmod 0440 /etc/sudoers.d/wheel
    
    # Create user
    info "Creating user $USERNAME..."
    useradd -m -G users,wheel,audio,video,usb,portage,plugdev -s /bin/bash "$USERNAME" || die "Failed to create user"
    
    # Set user password
    echo "Please enter a password for user $USERNAME:"
    passwd "$USERNAME"
    
    # Create user directories
    mkdir -p "/home/$USERNAME"/{Documents,Downloads,Pictures,Videos}
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"
    
    info "User account created successfully"
}

# Execute main function
main "$@"