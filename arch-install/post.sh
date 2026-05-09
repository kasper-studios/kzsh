#!/usr/bin/env bash
set -euo pipefail

# Source common functions
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/lib/common.sh"

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
        *) shift ;;
    esac
done

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

info "Installing bootloader (systemd-boot)..."
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

cat > /boot/loader/entries/arch.conf << EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=UUID=$ROOT_UUID rootflags=subvol=@ rw
EOF

info "Updating initramfs..."
mkinitcpio -P

info "Enabling services..."
systemctl enable NetworkManager

# Run profile if exists
if [[ -f "${SCRIPT_DIR}/profiles/${PROFILE}.sh" ]]; then
    info "Running profile: $PROFILE"
    bash "${SCRIPT_DIR}/profiles/${PROFILE}.sh"
else
    warn "Profile ${PROFILE} not found, skipping."
fi

success "Stage 2 (Post-install) complete."
info "You can now exit, umount -R /mnt, and reboot."
