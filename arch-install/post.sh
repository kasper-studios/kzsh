#!/usr/bin/env bash
set -euo pipefail

# Source common functions
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/lib/common.sh"

# Load installation metadata from prep.sh
if [[ -f "${SCRIPT_DIR}/.install-meta" ]]; then
    source "${SCRIPT_DIR}/.install-meta"
else
    warn "Installation metadata not found, using defaults"
    BOOT_MODE="uefi"
    BOOTLOADER="systemd-boot"
    FILESYSTEM="btrfs"
    DISK=""
fi

# Default values
HOSTNAME="kasarch"
USERNAME="kasper"
PROFILE="base"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --hostname) HOSTNAME="$2"; shift 2 ;;
        --user) USERNAME="$2"; shift 2 ;;
        --profile) PROFILE="$2"; shift 2 ;;
        --debug) DEBUG=1; shift ;;
        *) shift ;;
    esac
done

info "Post-install configuration:"
info "  Boot Mode: $BOOT_MODE"
info "  Bootloader: $BOOTLOADER"
info "  Filesystem: $FILESYSTEM"
info "  Hostname: $HOSTNAME"
info "  Username: $USERNAME"
info "  Profile: $PROFILE"

info "Setting timezone and locale..."
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

info "Setting hostname..."
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

info "Configuring users..."
# Set root password interactively
info "Set root password:"
passwd

# Create user
useradd -m -G wheel -s /usr/bin/zsh "$USERNAME"
info "Set password for $USERNAME:"
passwd "$USERNAME"

# Enable sudo for wheel
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

info "Installing bootloader..."

if [[ "$BOOTLOADER" == "systemd-boot" ]]; then
    if [[ "$BOOT_MODE" != "uefi" ]]; then
        error "systemd-boot requires UEFI mode"
    fi
    
    info "Installing systemd-boot..."
    bootctl install

    # Get UUID of the ROOT partition
    ROOT_PART=$(findmnt -no SOURCE /)
    ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")

    cat > /boot/loader/loader.conf << EOF
default arch.conf
timeout 3
console-mode max
editor no
EOF

    # Build kernel options based on filesystem
    KERNEL_OPTS="root=UUID=$ROOT_UUID rw"
    if [[ "$FILESYSTEM" == "btrfs" ]]; then
        KERNEL_OPTS="$KERNEL_OPTS rootflags=subvol=@"
    fi

    cat > /boot/loader/entries/arch.conf << EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options $KERNEL_OPTS
EOF

elif [[ "$BOOTLOADER" == "grub" ]]; then
    info "Installing GRUB..."
    
    if [[ "$BOOT_MODE" == "uefi" ]]; then
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    else
        if [[ -z "$DISK" ]]; then
            # Try to detect disk from root partition
            ROOT_PART=$(findmnt -no SOURCE /)
            DISK=$(lsblk -no PKNAME "$ROOT_PART" | head -n1)
            DISK="/dev/$DISK"
        fi
        info "Installing GRUB to $DISK (BIOS mode)"
        grub-install --target=i386-pc "$DISK"
    fi
    
    # Configure GRUB for BTRFS if needed
    if [[ "$FILESYSTEM" == "btrfs" ]]; then
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&rootflags=subvol=@ /' /etc/default/grub
    fi
    
    grub-mkconfig -o /boot/grub/grub.cfg
else
    error "Unknown bootloader: $BOOTLOADER"
fi

info "Updating initramfs..."
mkinitcpio -P

info "Enabling services..."
systemctl enable NetworkManager

# Run profile if exists
if [[ "$PROFILE" != "none" ]]; then
    if [[ -f "${SCRIPT_DIR}/profiles/${PROFILE}.sh" ]]; then
        info "Running profile: $PROFILE"
        bash "${SCRIPT_DIR}/profiles/${PROFILE}.sh"
    else
        warn "Profile ${PROFILE} not found, skipping."
    fi
fi

# Cleanup metadata file
rm -f "${SCRIPT_DIR}/.install-meta"

success "Stage 2 (Post-install) complete."
info ""
info "Next steps:"
info "  1. Exit the chroot: exit"
info "  2. Unmount partitions: umount -R /mnt"
info "  3. Reboot: reboot"
info ""
info "System details:"
info "  Boot Mode: $BOOT_MODE"
info "  Bootloader: $BOOTLOADER"
info "  Filesystem: $FILESYSTEM"
