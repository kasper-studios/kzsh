#!/bin/bash
# Installation verification script
# Can be run from ArchISO or inside chroot

set -uo pipefail

INSTALL_ROOT="${1:-/mnt}"
ERRORS=0
WARNINGS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

error() {
    echo -e "${RED}✗ ERROR:${NC} $1"
    ((ERRORS++))
}

warn() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $1"
    ((WARNINGS++))
}

ok() {
    echo -e "${GREEN}✓${NC} $1"
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

section() {
    echo ""
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Detect if we're in chroot or ArchISO
if [[ -f /.install-meta ]] || [[ -f /root/arch-install/.install-meta ]]; then
    IN_CHROOT=1
    INSTALL_ROOT="/"
    info "Running inside chroot environment"
else
    IN_CHROOT=0
    info "Running from ArchISO, checking $INSTALL_ROOT"
fi

section "Partition Check"

# Check if install root is mounted
if ! mountpoint -q "$INSTALL_ROOT" 2>/dev/null; then
    error "Install root $INSTALL_ROOT is not mounted"
else
    ok "Install root mounted at $INSTALL_ROOT"
    ROOT_PART=$(findmnt -no SOURCE "$INSTALL_ROOT")
    ROOT_FS=$(findmnt -no FSTYPE "$INSTALL_ROOT")
    info "Root partition: $ROOT_PART ($ROOT_FS)"
fi

# Check boot partition
if [[ -d "$INSTALL_ROOT/boot" ]]; then
    if mountpoint -q "$INSTALL_ROOT/boot" 2>/dev/null; then
        ok "Boot partition mounted"
        BOOT_PART=$(findmnt -no SOURCE "$INSTALL_ROOT/boot")
        BOOT_FS=$(findmnt -no FSTYPE "$INSTALL_ROOT/boot")
        info "Boot partition: $BOOT_PART ($BOOT_FS)"
        
        if [[ "$BOOT_FS" != "vfat" ]]; then
            error "Boot partition is not FAT32 (found: $BOOT_FS)"
        else
            ok "Boot partition is FAT32"
        fi
    else
        error "Boot partition not mounted at $INSTALL_ROOT/boot"
    fi
else
    error "Boot directory $INSTALL_ROOT/boot does not exist"
fi

section "BTRFS Subvolumes Check"

if [[ "$ROOT_FS" == "btrfs" ]]; then
    ok "BTRFS filesystem detected"
    
    # Check subvolumes
    SUBVOLS=("@" "@home" "@log" "@pkg")
    for subvol in "${SUBVOLS[@]}"; do
        if btrfs subvolume show "$INSTALL_ROOT" 2>/dev/null | grep -q "Name:.*$subvol"; then
            ok "Subvolume $subvol exists"
        else
            warn "Subvolume $subvol not found"
        fi
    done
    
    # Check if @ is mounted
    if findmnt -no OPTIONS "$INSTALL_ROOT" | grep -q "subvol=@"; then
        ok "Root mounted with subvol=@"
    else
        warn "Root not mounted with subvol=@ option"
    fi
fi

section "Bootloader Check"

# Check for systemd-boot
if [[ -d "$INSTALL_ROOT/boot/EFI/systemd" ]]; then
    ok "systemd-boot installed"
    
    # Check loader.conf
    if [[ -f "$INSTALL_ROOT/boot/loader/loader.conf" ]]; then
        ok "loader.conf exists"
    else
        error "loader.conf missing"
    fi
    
    # Check boot entries
    if [[ -d "$INSTALL_ROOT/boot/loader/entries" ]]; then
        ENTRY_COUNT=$(ls -1 "$INSTALL_ROOT/boot/loader/entries/"*.conf 2>/dev/null | wc -l)
        if [[ $ENTRY_COUNT -gt 0 ]]; then
            ok "Found $ENTRY_COUNT boot entry/entries"
            for entry in "$INSTALL_ROOT/boot/loader/entries/"*.conf; do
                info "  - $(basename "$entry")"
            done
        else
            error "No boot entries found in /boot/loader/entries/"
        fi
    else
        error "Boot entries directory missing"
    fi
    
    # Check kernel and initramfs
    if [[ -f "$INSTALL_ROOT/boot/vmlinuz-linux" ]]; then
        ok "Kernel image found"
    else
        error "Kernel image missing"
    fi
    
    if [[ -f "$INSTALL_ROOT/boot/initramfs-linux.img" ]]; then
        ok "Initramfs found"
    else
        error "Initramfs missing"
    fi
    
    # Check microcode
    if [[ -f "$INSTALL_ROOT/boot/intel-ucode.img" ]]; then
        ok "Intel microcode found"
    fi
    if [[ -f "$INSTALL_ROOT/boot/amd-ucode.img" ]]; then
        ok "AMD microcode found"
    fi
    
elif [[ -d "$INSTALL_ROOT/boot/grub" ]]; then
    ok "GRUB installed"
    
    if [[ -f "$INSTALL_ROOT/boot/grub/grub.cfg" ]]; then
        ok "grub.cfg exists"
    else
        error "grub.cfg missing"
    fi
else
    error "No bootloader found (neither systemd-boot nor GRUB)"
fi

section "System Configuration Check"

# Check fstab
if [[ -f "$INSTALL_ROOT/etc/fstab" ]]; then
    ok "fstab exists"
    FSTAB_ENTRIES=$(grep -v '^#' "$INSTALL_ROOT/etc/fstab" | grep -v '^$' | wc -l)
    info "fstab has $FSTAB_ENTRIES entries"
    
    # Check if root is in fstab
    if grep -q "/ " "$INSTALL_ROOT/etc/fstab"; then
        ok "Root partition in fstab"
    else
        error "Root partition not in fstab"
    fi
    
    # Check if boot is in fstab (for UEFI)
    if grep -q "/boot " "$INSTALL_ROOT/etc/fstab"; then
        ok "Boot partition in fstab"
    else
        warn "Boot partition not in fstab (may be intentional)"
    fi
else
    error "fstab missing"
fi

# Check hostname
if [[ -f "$INSTALL_ROOT/etc/hostname" ]]; then
    HOSTNAME=$(cat "$INSTALL_ROOT/etc/hostname")
    ok "Hostname set to: $HOSTNAME"
else
    error "Hostname not configured"
fi

# Check locale
if [[ -f "$INSTALL_ROOT/etc/locale.conf" ]]; then
    ok "Locale configured"
else
    warn "Locale not configured"
fi

# Check users
if [[ -f "$INSTALL_ROOT/etc/passwd" ]]; then
    USER_COUNT=$(grep -v 'nologin\|false' "$INSTALL_ROOT/etc/passwd" | grep -v '^root:' | wc -l)
    if [[ $USER_COUNT -gt 0 ]]; then
        ok "Found $USER_COUNT user account(s)"
    else
        warn "No user accounts found (only root)"
    fi
fi

section "Network Configuration Check"

# Check NetworkManager
if [[ -f "$INSTALL_ROOT/usr/bin/NetworkManager" ]]; then
    ok "NetworkManager installed"
    
    # Check if enabled (only works in chroot)
    if [[ $IN_CHROOT -eq 1 ]]; then
        if systemctl is-enabled NetworkManager &>/dev/null; then
            ok "NetworkManager enabled"
        else
            warn "NetworkManager not enabled"
        fi
    fi
else
    warn "NetworkManager not installed"
fi

section "Summary"

echo ""
if [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo "System is ready to boot."
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) found${NC}"
    echo "System should boot, but review warnings above."
else
    echo -e "${RED}✗ $ERRORS error(s) and $WARNINGS warning(s) found${NC}"
    echo "System may not boot correctly. Fix errors above."
    exit 1
fi

echo ""
