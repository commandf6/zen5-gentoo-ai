#!/bin/bash
# =============================================================================
# 6-install-base.sh - Install Gentoo stage3 and prepare chroot
# =============================================================================

set -euo pipefail
trap 'echo "[!] Error on line $LINENO: $BASH_COMMAND"; exit 1' ERR

# Script directory detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Source functions
source "$SCRIPT_DIR/functions.sh"

# Configuration
MARKER="/tmp/.06-base.done"
MOUNT_ROOT="/mnt/gentoo"

main() {
    # Check if already done
    if check_marker "$MARKER"; then
        info "Base system already installed. Skipping."
        return 0
    fi

    # Parse configuration
    parse_config

    # Basic checks
    verify_root_user

    # Required commands
    check_command "wget" "net-misc/wget"
    check_command "tar" "app-arch/tar"

    info "Installing Gentoo base system..."

    # Select stage3 tarball
    info "Selecting and downloading stage3 tarball..."
    select_stage3_tarball
    
    # Switch to the target mount
    cd "$MOUNT_ROOT"

    # Verify target is mounted
    if ! mountpoint -q "$MOUNT_ROOT"; then
        die "Target directory $MOUNT_ROOT is not a mountpoint"
    fi

    # Back up resolver for network in chroot
    info "Backing up resolv.conf..."
    if [[ -f etc/resolv.conf ]]; then
        cp etc/resolv.conf /tmp/resolv.conf.backup
    fi

    # Extract stage3
    info "Extracting stage3 tarball..."
    if [[ -n "${STAGE3_URL:-}" && -n "${STAGE3_FILE:-}" ]]; then
        tar xpf "$STAGE3_FILE" --xattrs-include='*.*' --numeric-owner || die "Failed to extract stage3"
    else
        die "Stage3 tarball not defined"
    fi

    # Restore networking
    info "Restoring network configuration..."
    if [[ -f /tmp/resolv.conf.backup ]]; then
        cp /tmp/resolv.conf.backup etc/resolv.conf
    else
        cp --dereference /etc/resolv.conf etc/
    fi

    # Create make.conf and portage configuration
    info "Configuring portage..."
    setup_portage

    # Mount pseudo-filesystems
    info "Mounting pseudo-filesystems for chroot..."
    mount_pseudo_fs

    # Create chroot entry script
    info "Creating chroot entry script..."
    cat > "$MOUNT_ROOT/enter-chroot.sh" <<'EOF'
#!/bin/bash
echo "Entering chroot environment..."
chroot /mnt/gentoo /bin/bash
EOF
    chmod +x "$MOUNT_ROOT/enter-chroot.sh"

    create_marker "$MARKER"
    info "Stage3 installation complete. Ready to chroot."
}

select_stage3_tarball() {
    local stage3_dir="$PARENT_DIR/stage3"
    mkdir -p "$stage3_dir"
    
    # Check if a stage3 is already provided
    if [[ -f "$stage3_dir"/stage3-*.tar.* ]]; then
        STAGE3_FILE=$(find "$stage3_dir" -name "stage3-*.tar.*" | head -1)
        info "Using existing stage3 tarball: $STAGE3_FILE"
        return 0
    fi
    
    # Offer to download stage3
    echo
    echo "Stage3 tarball options:"
    echo "1) Latest AMD64 desktop (OpenRC)"
    echo "2) Latest AMD64 desktop (systemd)"
    echo "3) Specify URL manually"
    echo "4) Use local file"
    echo
    read -p "Select option [1]: " stage3_option
    stage3_option=${stage3_option:-1}
    
    case "$stage3_option" in
        1)
            info "Downloading latest AMD64 desktop (OpenRC) stage3..."
            cd "$stage3_dir"
            wget -q https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-desktop-openrc.txt
            STAGE3_URL=$(grep -v "^#" latest-stage3-amd64-desktop-openrc.txt | cut -d' ' -f1)
            STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/$STAGE3_URL"
            STAGE3_FILE="$stage3_dir/$(basename "$STAGE3_URL")"
            wget -O "$STAGE3_FILE" "$STAGE3_URL" || die "Failed to download stage3"
            ;;
        2)
            info "Downloading latest AMD64 desktop (systemd) stage3..."
            cd "$stage3_dir"
            wget -q https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-desktop-systemd.txt
            STAGE3_URL=$(grep -v "^#" latest-stage3-amd64-desktop-systemd.txt | cut -d' ' -f1)
            STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/$STAGE3_URL"
            STAGE3_FILE="$stage3_dir/$(basename "$STAGE3_URL")"
            wget -O "$STAGE3_FILE" "$STAGE3_URL" || die "Failed to download stage3"
            ;;
        3)
            read -p "Enter stage3 tarball URL: " STAGE3_URL
            STAGE3_FILE="$stage3_dir/$(basename "$STAGE3_URL")"
            info "Downloading from $STAGE3_URL..."
            wget -O "$STAGE3_FILE" "$STAGE3_URL" || die "Failed to download stage3"
            ;;
        4)
            read -p "Enter path to local stage3 tarball: " STAGE3_FILE
            if [[ ! -f "$STAGE3_FILE" ]]; then
                die "Local stage3 tarball not found: $STAGE3_FILE"
            fi
            ;;
        *)
            die "Invalid option"
            ;;
    esac
    
    info "Stage3 tarball selected: $STAGE3_FILE"
}

setup_portage() {
    # Create portage directories
    mkdir -p "$MOUNT_ROOT"/etc/portage/{package.use,package.accept_keywords,package.mask,package.unmask,repos.conf}
    
    # Copy the gentoo repository config
    cp "$MOUNT_ROOT"/usr/share/portage/config/repos.conf "$MOUNT_ROOT"/etc/portage/repos.conf/gentoo.conf
    
    # Create make.conf from template
    info "Creating make.conf..."
    cat > "$MOUNT_ROOT"/etc/portage/make.conf <<EOF
# Compiler flags optimized for AMD Zen 5
COMMON_FLAGS="-march=znver4 -O2 -pipe"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

# CPU optimization
CPU_FLAGS_X86="aes avx avx2 f16c fma3 mmx mmxext pclmul popcnt rdrand sha sse sse2 sse3 sse4_1 sse4_2 sse4a ssse3"
MAKEOPTS="-j32"
EMERGE_DEFAULT_OPTS="--jobs=16 --load-average=32"

# System profile
ACCEPT_KEYWORDS="amd64"
USE="X wayland gtk qt5 pulseaudio networkmanager dbus policykit \
     btrfs lvm device-mapper crypt luks \
     nvidia cuda opencl vulkan vaapi vdpau \
     python lua \
     zstd lz4"

# Hardware settings
VIDEO_CARDS="nvidia"
INPUT_DEVICES="libinput"

# Language support
L10N="en-US"
LINGUAS="en_US"

# Python targets
PYTHON_TARGETS="python3_11 python3_12"
PYTHON_SINGLE_TARGET="python3_11"

# Portage features
FEATURES="parallel-fetch parallel-install candy"
GENTOO_MIRRORS="https://mirrors.kernel.org/gentoo"

# Portage directories
PORTAGE_TMPDIR="/tensor_lab/var/tmp"
EOF

    # Create package.use for desktop
    cat > "$MOUNT_ROOT"/etc/portage/package.use/desktop <<EOF
# Desktop environment
sys-apps/dbus X
media-video/pipewire sound-server jack-sdk
gui-libs/gtk+ wayland
dev-qt/qtgui egl
media-libs/mesa wayland vulkan
x11-libs/libxcb X
EOF
}

mount_pseudo_fs() {
    info "Mounting pseudo-filesystems..."
    mount --types proc /proc "$MOUNT_ROOT/proc"
    mount --rbind /sys "$MOUNT_ROOT/sys"
    mount --make-rslave "$MOUNT_ROOT/sys"
    mount --rbind /dev "$MOUNT_ROOT/dev"
    mount --make-rslave "$MOUNT_ROOT/dev"
    mount --bind /run "$MOUNT_ROOT/run" || true
}

# Execute main function
main "$@"