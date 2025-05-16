Zen5 Gentoo AI - Troubleshooting Guide
This document covers common issues that may arise during installation and operation of the Zen5 Gentoo AI system.
Installation Issues
Missing Commands or Tools
Issue: Scripts fail with "command not found" errors.
Solution:
bash# Install required packages
emerge --ask sys-apps/gptfdisk      # For sgdisk
emerge --ask sys-block/parted       # For partprobe
emerge --ask sys-fs/cryptsetup      # For cryptsetup
emerge --ask sys-fs/lvm2            # For LVM tools
Partitioning Fails
Issue: Unable to partition disks due to "Device or resource busy" errors.
Solution:
bash# Check if disks are in use
lsblk
fuser -mv /dev/nvmeXnX

# Force close any open processes
fuser -mv /dev/nvmeXnX -k

# Try alternative partitioning method
fdisk /dev/nvmeXnX  # Manual partitioning
LUKS Encryption Issues
Issue: Failed to create or open LUKS volumes.
Solution:
bash# Check if device exists
ls -la /dev/nvmeXnX

# Verify LUKS format
cryptsetup isLuks /dev/nvmeXnX
cryptsetup luksDump /dev/nvmeXnX

# Try with alternate options
cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 /dev/nvmeXnX
LVM Issues
Issue: LVM setup fails.
Solution:
bash# Check LUKS container is open
ls -la /dev/mapper/

# Check for existing LVM 
vgscan
pvscan

# Remove existing LVM if needed
vgremove [volume_group]
pvremove /dev/mapper/crypt_*
Stage3 Download Problems
Issue: Cannot download or extract stage3 tarball.
Solution:
bash# Check internet connection
ping -c 3 gentoo.org

# Try alternate mirror
wget https://mirror.bytemark.co.uk/gentoo/releases/amd64/autobuilds/latest-stage3-amd64-desktop-openrc.txt
wget https://mirror.bytemark.co.uk/gentoo/releases/amd64/autobuilds/[stage3-url]

# Manual extraction
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo
Kernel Build Fails
Issue: Kernel compilation errors.
Solution:
bash# Ensure you have all required packages
emerge --ask sys-kernel/linux-firmware
emerge --ask sys-kernel/gentoo-sources

# Try with genkernel
emerge --ask sys-kernel/genkernel
genkernel all
Boot Issues
Cannot Boot Encrypted System
Issue: System fails to boot, asking for LUKS password but not proceeding.
Solution:
bash# Boot from live USB
# Mount and chroot into your system
cryptsetup open /dev/nvme0n1p3 crypt_root
mount -o subvol=@ /dev/mapper/vg_io-lv_io_root /mnt/gentoo
# (Mount other filesystems...)
chroot /mnt/gentoo /bin/bash
source /etc/profile

# Fix GRUB configuration
nano /etc/default/grub
# Ensure GRUB_CMDLINE_LINUX includes:
# rd.luks.uuid=[UUID] root=/dev/mapper/vg_io-lv_io_root rootfstype=btrfs rootflags=subvol=@

# Regenerate grub config
grub-mkconfig -o /boot/grub/grub.cfg

# Rebuild initramfs
dracut --force --kver $(ls -1 /lib/modules | sort | tail -1)
Missing Modules in Initramfs
Issue: Missing modules in initramfs, causing boot failure.
Solution:
bash# Fix dracut configuration
nano /etc/dracut.conf.d/encryption.conf
# Add the following:
add_dracutmodules+=" crypt dm rootfs-block lvm btrfs "
add_drivers+=" nvme btrfs dm_crypt dm_mod "

# Rebuild initramfs
dracut --force --kver $(ls -1 /lib/modules | sort | tail -1)
Post-Installation Issues
NVIDIA Driver Problems
Issue: NVIDIA drivers not loading or GPU not detected.
Solution:
bash# Check if modules are loaded
lsmod | grep nvidia

# Try loading modules manually
modprobe nvidia
modprobe nvidia_drm
modprobe nvidia_uvm

# Check kernel messages
dmesg | grep -i nvidia

# Reinstall drivers
emerge --unmerge x11-drivers/nvidia-drivers
emerge --ask x11-drivers/nvidia-drivers
Python or AI Environment Issues
Issue: Python virtual environment or AI tools not working.
Solution:
bash# Fix permissions
chown -R username:username /tensor_lab

# Recreate virtual environment
rm -rf /tensor_lab/venv
python -m venv /tensor_lab/venv

# Install packages manually
source /tensor_lab/venv/bin/activate
pip install torch torchvision torchaudio
pip install transformers datasets
File System Issues
Issue: Btrfs or LVM problems, read-only filesystem.
Solution:
bash# Check filesystem
btrfs check /dev/mapper/vg_io-lv_io_root

# Fix filesystem
btrfs check --repair /dev/mapper/vg_io-lv_io_root

# Check volume group status
vgdisplay vg_io
vgdisplay vg_tensor_lab

# Activate logical volumes
vgchange -ay vg_io
vgchange -ay vg_tensor_lab
Performance Tuning
GPU Memory Issues
Issue: Out of memory errors with large AI models.
Solution:
bash# Add to user's .bashrc or environment
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512

# Enable CPU offloading
pip install accelerate
CPU Performance Issues
Issue: Poor CPU performance during AI tasks.
Solution:
bash# Add to user's .bashrc
export OMP_NUM_THREADS=32  # adjust to your CPU core count
export MKL_NUM_THREADS=32  # for Intel MKL

# Set CPU governor to performance
echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
Contact & Resources
If you encounter issues not addressed in this guide, please:

Check the official Gentoo documentation: https://wiki.gentoo.org/
Search the Gentoo forums: https://forums.gentoo.org/
File an issue on the project repository

For AI-specific configuration, the PyTorch documentation is a valuable resource: https://pytorch.org/docs/stable/index.html