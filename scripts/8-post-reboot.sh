#!/bin/bash
# =============================================================================
# 8-post-reboot.sh - Post-reboot configuration
# =============================================================================

set -euo pipefail
trap 'echo "[!] Error on line $LINENO: $BASH_COMMAND"; exit 1' ERR

# Script directory detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Source functions
source "$SCRIPT_DIR/functions.sh"

# Configuration
MARKER="/tmp/.08-post-reboot.done"

main() {
    # Check if already done
    if check_marker "$MARKER"; then
        info "Post-reboot configuration already completed. Skipping."
        return 0
    fi

    # Parse configuration
    parse_config

    # Basic checks
    verify_root_user

    info "Starting post-reboot configuration..."

    # Verify LUKS and LVM is working
    verify_encryption
    
    # Install NVIDIA drivers
    info "Installing NVIDIA drivers and CUDA..."
    install_nvidia
    
    # Setup AI environment
    info "Setting up AI/ML environment..."
    setup_ai_environment
    
    # Install monitoring tools
    info "Installing system monitoring tools..."
    install_monitoring
    
    # Install graphical environment (optional)
    info "Installing graphical environment..."
    install_gui
    
    # Final touches
    info "Performing final configuration..."
    final_configuration

    create_marker "$MARKER"
    info "Post-reboot configuration complete"
    
    echo
    echo "Your Zen5 Gentoo AI system is now fully configured!"
    echo "Reboot to start using it, or log in as $USERNAME to begin."
}

verify_encryption() {
    info "Verifying encryption setup..."
    
    # Check if encrypted volumes are mounted
    if ! mount | grep -q "on / type btrfs"; then
        die "Root filesystem not properly mounted"
    fi
    
    if ! mount | grep -q "on /tensor_lab type btrfs"; then
        warn "Tensor lab filesystem not mounted"
        if confirm_action "Try to mount /tensor_lab?"; then
            mount /tensor_lab || warn "Failed to mount tensor_lab (non-fatal)"
        fi
    fi
    
    # Verify swap
    if ! swapon --show | grep -q "${VG_OS}-${LV_SWAP}"; then
        warn "Swap not activated"
        if confirm_action "Activate swap?"; then
            swapon /dev/mapper/${VG_OS}-${LV_SWAP} || warn "Failed to activate swap (non-fatal)"
        fi
    fi
    
    info "Encryption verification complete"
}

install_nvidia() {
    # Ask user if they want to install NVIDIA drivers
    if ! confirm_action "Install NVIDIA drivers and CUDA?"; then
        info "Skipping NVIDIA installation"
        return 0
    fi
    
    # Install NVIDIA drivers and CUDA
    info "Installing NVIDIA drivers..."
    emerge --ask x11-drivers/nvidia-drivers \
           media-libs/libglvnd \
           x11-libs/libX11 \
           x11-libs/libXext \
           virtual/opengl || warn "NVIDIA driver installation had errors (non-fatal)"
    
    # Optional: Install CUDA toolkit
    if confirm_action "Install CUDA toolkit? (may take a long time)"; then
        emerge --ask dev-util/nvidia-cuda-toolkit || warn "CUDA toolkit installation had errors (non-fatal)"
    fi
    
    # Configure NVIDIA kernel modules
    info "Configuring NVIDIA kernel modules..."
    mkdir -p /etc/modprobe.d /etc/modules-load.d
    
    cat > /etc/modprobe.d/nvidia.conf <<EOF
options nvidia_drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF
    
    cat > /etc/modules-load.d/nvidia.conf <<EOF
nvidia
nvidia_modeset
nvidia_uvm
nvidia_drm
EOF

    # Enable persistence daemon
    if ! rc-update show | grep -q "nvidia-persistenced"; then
        rc-update add nvidia-persistenced default
    fi
    
    # Add user to video and render groups
    usermod -aG video,render "$USERNAME"
    
    info "NVIDIA setup complete"
}

setup_ai_environment() {
    # Ask user if they want to set up AI environment
    if ! confirm_action "Set up AI/ML environment?"; then
        info "Skipping AI environment setup"
        return 0
    fi
    
    # Create directory structure
    info "Creating AI workspace directories..."
    mkdir -p /tensor_lab/{models,datasets,notebooks,projects,src,cache,venv}
    
    # Install Python and core ML packages
    info "Installing Python and core libraries..."
    emerge --ask dev-lang/python dev-python/pip dev-python/virtualenv || warn "Python installation had errors (non-fatal)"
    emerge --ask dev-python/numpy dev-python/scipy dev-python/pandas || warn "Python libraries installation had errors (non-fatal)"
    
    # Optional: Install JupyterLab
    if confirm_action "Install JupyterLab?"; then
        emerge --ask dev-python/jupyterlab || warn "JupyterLab installation had errors (non-fatal)"
    fi
    
    # Create Python virtual environment
    info "Creating Python virtual environment..."
    chown -R "$USERNAME:$USERNAME" /tensor_lab
    su - "$USERNAME" -c "python -m venv /tensor_lab/venv"
    
    # Install PyTorch and related packages
    if confirm_action "Install PyTorch and related packages to virtual environment?"; then
        info "Installing PyTorch to virtual environment..."
        su - "$USERNAME" -c "source /tensor_lab/venv/bin/activate && pip install torch torchvision torchaudio"
        
        if confirm_action "Install transformers and related libraries?"; then
            su - "$USERNAME" -c "source /tensor_lab/venv/bin/activate && pip install transformers datasets accelerate"
        fi
    fi
    
    # Create user environment shortcuts
    info "Setting up user environment..."
    cat >> "/home/$USERNAME/.bash_profile" <<EOF

# AI Tools Environment
alias ai='source /tensor_lab/venv/bin/activate'

# CUDA paths
export CUDA_HOME=/opt/cuda
export PATH=\$PATH:\$CUDA_HOME/bin
export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:\$CUDA_HOME/lib64

# GPU tuning
export CUDA_VISIBLE_DEVICES=0
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
EOF
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.bash_profile"
    
    info "AI environment setup complete"
}

install_monitoring() {
    # Ask user if they want to install monitoring tools
    if ! confirm_action "Install system monitoring tools?"; then
        info "Skipping monitoring tools installation"
        return 0
    fi
    
    # Install monitoring tools
    info "Installing system monitoring tools..."
    emerge --ask \
        sys-process/htop \
        sys-process/btop \
        app-admin/glances \
        sys-apps/nvme-cli || warn "Monitoring tools installation had errors (non-fatal)"
    
    # Install NVIDIA monitoring
    emerge --ask media-video/nvtop || warn "NVTOP installation had errors (non-fatal)"
    
    info "Monitoring tools installation complete"
}

install_gui() {
    # Ask user if they want to install a GUI
    echo
    echo "Graphical environment options:"
    echo "1) None - Console only"
    echo "2) Hyprland (Wayland compositor)"
    echo "3) KDE Plasma"
    echo "4) GNOME"
    echo "5) Xfce"
    echo
    read -p "Select option [1]: " gui_option
    gui_option=${gui_option:-1}
    
    case "$gui_option" in
        1)
            info "Skipping GUI installation"
            return 0
            ;;
        2)
            install_hyprland
            ;;
        3)
            install_kde
            ;;
        4)
            install_gnome
            ;;
        5)
            install_xfce
            ;;
        *)
            warn "Invalid option, skipping GUI installation"
            return 0
            ;;
    esac
}

install_hyprland() {
    info "Installing Hyprland Wayland compositor..."
    
    # Install dependencies
    emerge --ask \
        sys-apps/dbus \
        sys-auth/elogind \
        sys-auth/polkit \
        media-libs/mesa \
        dev-libs/wayland \
        gui-wm/hyprland \
        gui-apps/waybar \
        gui-apps/foot \
        gui-apps/wofi \
        gui-apps/mako \
        gui-apps/wl-clipboard \
        media-video/pipewire || warn "Hyprland installation had errors"
    
    # Create configuration directory
    mkdir -p "/home/$USERNAME/.config/hypr"
    
    # Create basic config
    cat > "/home/$USERNAME/.config/hypr/hyprland.conf" <<'EOF'
# Hyprland Configuration

monitor=,preferred,auto,1.0

exec-once = dbus-launch --exit-with-session
exec-once = waybar
exec-once = mako

env = XCURSOR_SIZE,24
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = GDK_BACKEND,wayland
env = SDL_VIDEODRIVER,wayland
env = LIBVA_DRIVER_NAME,nvidia
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = WLR_NO_HARDWARE_CURSORS,1

input {
    kb_layout = us
    follow_mouse = 1
    sensitivity = 0
    accel_profile = flat
}

general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
    col.inactive_border = rgba(595959aa)
    layout = dwindle
}

decoration {
    rounding = 10
    drop_shadow = true
    shadow_range = 4
    shadow_render_power = 3
}

animations {
    enabled = true
    bezier = myBezier,0.05,0.9,0.1,1.05
    animation = windows,1,5,myBezier
    animation = windowsOut,1,7,default,popin 80%
    animation = fade,1,7,default
    animation = workspaces,1,6,default
}

dwindle {
    pseudotile = true
    preserve_split = true
}

$mainMod = SUPER

bind = $mainMod,Return,exec,foot
bind = $mainMod,Q,killactive,
bind = $mainMod,SHIFT+E,exit,
bind = $mainMod,D,exec,wofi --show drun
bind = $mainMod,V,togglefloating,
bind = $mainMod,F,fullscreen,

bind = $mainMod,left,movefocus,l
bind = $mainMod,right,movefocus,r
bind = $mainMod,up,movefocus,u
bind = $mainMod,down,movefocus,d

bind = $mainMod,1,workspace,1
bind = $mainMod,2,workspace,2
bind = $mainMod,3,workspace,3
bind = $mainMod,4,workspace,4
bind = $mainMod,5,workspace,5

bind = $mainMod,SHIFT+1,movetoworkspace,1
bind = $mainMod,SHIFT+2,movetoworkspace,2
bind = $mainMod,SHIFT+3,movetoworkspace,3
bind = $mainMod,SHIFT+4,movetoworkspace,4
bind = $mainMod,SHIFT+5,movetoworkspace,5
EOF
    
    # Set ownership
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.config"
    
    # Environment setup for Wayland/Hyprland
    cat >> "/home/$USERNAME/.bash_profile" <<EOF

# Wayland/Hyprland environment
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
EOF
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.bash_profile"
    
    info "Hyprland installation complete"
}

install_kde() {
    info "Installing KDE Plasma..."
    
    # Install KDE Plasma
    emerge --ask kde-plasma/plasma-meta || warn "KDE installation had errors"
    
    # Configure display manager
    if confirm_action "Install SDDM display manager?"; then
        emerge --ask gui-libs/display-manager-init kde-plasma/sddm-kcm
        rc-update add display-manager default
    fi
    
    info "KDE Plasma installation complete"
}

install_gnome() {
    info "Installing GNOME..."
    
    # Install GNOME
    emerge --ask gnome-base/gnome || warn "GNOME installation had errors"
    
    # Configure display manager
    if confirm_action "Install GDM display manager?"; then
        emerge --ask gui-libs/display-manager-init gnome-base/gdm
        rc-update add display-manager default
    fi
    
    info "GNOME installation complete"
}

install_xfce() {
    info "Installing Xfce..."
    
    # Install Xfce
    emerge --ask xfce-base/xfce4-meta || warn "Xfce installation had errors"
    
    # Configure display manager
    if confirm_action "Install LightDM display manager?"; then
        emerge --ask gui-libs/display-manager-init x11-misc/lightdm
        rc-update add display-manager default
    fi
    
    info "Xfce installation complete"
}

final_configuration() {
    # Set up automatic updates
    if confirm_action "Set up automatic security updates?"; then
        info "Setting up automatic updates..."
        
        # Install cronie
        emerge --ask sys-process/cronie || warn "Cronie installation had errors"
        rc-update add cronie default
        
        # Create update script
        cat > /usr/local/bin/autoupdate.sh <<'EOF'
#!/bin/bash
# Update Portage tree
emerge --sync

# Update security-related packages
emerge --update --deep --newuse --verbose @security

# Clean up
eclean-dist -d
EOF
        chmod +x /usr/local/bin/autoupdate.sh
        
        # Add cron job
        echo "0 3 * * 0 /usr/local/bin/autoupdate.sh > /var/log/autoupdate.log 2>&1" | crontab -
    fi
    
    # Set up firewall
    if confirm_action "Set up UFW firewall?"; then
        info "Setting up firewall..."
        
        # Install UFW
        emerge --ask net-firewall/ufw || warn "UFW installation had errors"
        
        # Configure UFW
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow ssh
        ufw --force enable
        
        # Enable at boot
        rc-update add ufw default
    fi
    
    # Final system update
    if confirm_action "Perform a final system update?"; then
        info "Updating system packages..."
        emerge --update --deep --newuse @world
    fi
    
    info "Final configuration complete"
}

# Execute main function
main "$@"