#!/usr/bin/env bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging
info() { printf "${BLUE}[INFO]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; exit 1; }
success() { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
debug() { [[ "${DEBUG:-0}" == "1" ]] && printf "${CYAN}[DEBUG]${NC} %s\n" "$1"; }

# Boot mode detection
detect_boot_mode() {
    if [[ -d /sys/firmware/efi ]]; then
        echo "uefi"
    else
        echo "bios"
    fi
}

# Checks
check_boot_mode() {
    BOOT_MODE=$(detect_boot_mode)
    if [[ "$BOOT_MODE" == "uefi" ]]; then
        info "Detected UEFI boot mode"
    else
        info "Detected BIOS/Legacy boot mode"
    fi
}

check_internet() {
    info "Checking internet connection..."
    if ! ping -c 1 -W 3 archlinux.org &>/dev/null; then
        error "No internet connection detected."
    fi
}

check_disk_size() {
    local disk="$1"
    local min_size_gb=8
    local size_bytes=$(blockdev --getsize64 "$disk")
    local size_gb=$((size_bytes / 1024 / 1024 / 1024))
    
    if [[ $size_gb -lt $min_size_gb ]]; then
        error "Disk too small: ${size_gb}GB (minimum ${min_size_gb}GB required)"
    fi
    debug "Disk size: ${size_gb}GB"
}

# Confirmation
confirm_strict() {
    local target="$1"
    warn "THIS WILL ERASE ALL DATA ON ${target}!"
    echo -n "Type 'ERASE' to continue: "
    read -r confirmation
    if [[ "$confirmation" != "ERASE" ]]; then
        error "Aborted by user."
    fi
}

# Helper to find partitions based on disk name and boot mode
get_partitions() {
    local disk="$1"
    local boot_mode="${2:-uefi}"
    
    if [[ "$disk" == *"nvme"* ]] || [[ "$disk" == *"mmcblk"* ]]; then
        if [[ "$boot_mode" == "uefi" ]]; then
            BOOT_PART="${disk}p1"
            ROOT_PART="${disk}p2"
        else
            # BIOS: no separate boot partition needed with GRUB on BTRFS
            ROOT_PART="${disk}p1"
        fi
    else
        if [[ "$boot_mode" == "uefi" ]]; then
            BOOT_PART="${disk}1"
            ROOT_PART="${disk}2"
        else
            ROOT_PART="${disk}1"
        fi
    fi
}

# Validate profile exists
validate_profile() {
    local profile="$1"
    local script_dir="$2"
    
    if [[ "$profile" == "none" ]]; then
        return 0
    fi
    
    if [[ ! -f "${script_dir}/profiles/${profile}.sh" ]]; then
        error "Profile '${profile}' not found in ${script_dir}/profiles/"
    fi
    
    info "Profile '${profile}' validated"
}

# Cleanup on error
cleanup_on_error() {
    warn "Cleaning up after error..."
    if mountpoint -q /mnt; then
        umount -R /mnt 2>/dev/null || true
    fi
    swapoff -a 2>/dev/null || true
}

# Set trap for cleanup
trap cleanup_on_error ERR
