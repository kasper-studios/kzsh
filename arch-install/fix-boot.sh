#!/bin/bash
# Quick fix for systemd-boot configuration
# Run this in chroot: arch-chroot /mnt /root/arch-install/fix-boot.sh

set -euo pipefail

echo "=== systemd-boot Quick Fix ==="
echo ""

# Check if we're in chroot
if [[ ! -f /.install-meta ]] && [[ ! -f /root/arch-install/.install-meta ]]; then
    echo "Warning: Not in installation environment, but continuing..."
fi

# Ensure directories exist
echo "Creating boot loader directories..."
mkdir -p /boot/loader/entries
mkdir -p /boot/EFI/Linux

# Get root partition info
ROOT_PART=$(findmnt -no SOURCE /)
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
FILESYSTEM=$(findmnt -no FSTYPE /)

echo "Root partition: $ROOT_PART"
echo "Root UUID: $ROOT_UUID"
echo "Filesystem: $FILESYSTEM"
echo ""

# Build kernel options
KERNEL_OPTS="root=UUID=$ROOT_UUID rw"
if [[ "$FILESYSTEM" == "btrfs" ]]; then
    KERNEL_OPTS="$KERNEL_OPTS rootflags=subvol=@"
    echo "BTRFS detected, adding subvol=@ option"
fi

# Create loader.conf
echo "Creating /boot/loader/loader.conf..."
cat > /boot/loader/loader.conf << EOF
default arch.conf
timeout 3
console-mode max
editor no
EOF

# Build initrd lines based on available microcode
INITRD_LINES="initrd  /initramfs-linux.img"
if [[ -f /boot/intel-ucode.img ]]; then
    INITRD_LINES="initrd  /intel-ucode.img\n$INITRD_LINES"
    echo "Intel microcode found, adding to boot entry"
fi
if [[ -f /boot/amd-ucode.img ]]; then
    INITRD_LINES="initrd  /amd-ucode.img\n$INITRD_LINES"
    echo "AMD microcode found, adding to boot entry"
fi

# Create boot entry
echo "Creating /boot/loader/entries/arch.conf..."
printf "title   Arch Linux\nlinux   /vmlinuz-linux\n%b\noptions %s\n" \
    "$INITRD_LINES" "$KERNEL_OPTS" > /boot/loader/entries/arch.conf

echo ""
echo "=== Boot entry created ==="
cat /boot/loader/entries/arch.conf
echo ""

# Reinstall systemd-boot to update EFI variables
echo "Reinstalling systemd-boot..."
bootctl install --esp-path=/boot 2>&1 || echo "Warning: bootctl install had issues (may be normal in chroot)"

echo ""
echo "✓ systemd-boot configuration fixed!"
echo ""
echo "Next steps:"
echo "  1. Exit chroot: exit"
echo "  2. Unmount: umount -l /mnt"
echo "  3. Reboot: reboot"
