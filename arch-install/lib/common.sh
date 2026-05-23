#!/usr/bin/env bash
set -uo pipefail

# Enable debug mode if DEBUG=1
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x
fi

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

# ============================================
# BOOT MODE DETECTION
# ============================================
detect_boot_mode() {
    debug "detect_boot_mode called"
    if [[ -d /sys/firmware/efi ]]; then
        debug "UEFI directory found"
        echo "uefi"
    else
        debug "UEFI directory not found, assuming BIOS"
        echo "bios"
    fi
}

check_boot_mode() {
    debug "check_boot_mode called"
    BOOT_MODE=$(detect_boot_mode)
    if [[ "$BOOT_MODE" == "uefi" ]]; then
        info "Detected UEFI boot mode"
    else
        info "Detected BIOS/Legacy boot mode"
    fi
}

# ============================================
# DISTRIBUTION DETECTION & VALIDATION
# ============================================
detect_distro() {
    debug "detect_distro called"
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        debug "Detected distro: $ID"
        echo "$ID"
    else
        debug "No os-release found, returning unknown"
        echo "unknown"
    fi
}

# Check if distro is supported
is_distro_supported() {
    local distro="$1"
    debug "is_distro_supported called with: $distro"
    case "$distro" in
        arch|manjaro|endeavouros|garuda) 
            debug "Distro $distro is supported"
            return 0 ;;
        *) 
            debug "Distro $distro is not supported"
            return 1 ;;
    esac
}

# ============================================
# NETWORK CHECK
# ============================================
check_internet() {
    debug "check_internet called"
    info "Checking internet connection..."
    if ! ping -c 1 -W 3 archlinux.org &>/dev/null; then
        error "No internet connection detected."
    fi
    debug "check_internet passed"
}

# ============================================
# DISK VALIDATION
# ============================================
check_disk_size() {
    local disk="$1"
    local min_size_gb=8
    debug "check_disk_size called with: $disk"
    local size_bytes
    size_bytes=$(blockdev --getsize64 "$disk" 2>/dev/null) || {
        error "Failed to get disk size for $disk"
    }
    local size_gb=$((size_bytes / 1024 / 1024 / 1024))
    
    if [[ $size_gb -lt $min_size_gb ]]; then
        error "Disk too small: ${size_gb}GB (minimum ${min_size_gb}GB required)"
    fi
    debug "Disk size: ${size_gb}GB"
}

# Validate disk exists and is not system disk
validate_disk() {
    local disk="$1"
    debug "validate_disk called with: $disk"
    
    if [[ ! -b "$disk" ]]; then
        error "Disk not found: $disk"
    fi
    
    # Check if disk is mounted
    if mount | grep -q "^$disk"; then
        error "Disk $disk is currently mounted"
    fi
    
    # Check if disk is the root disk (avoid using lsblk to prevent errors)
    local root_device=$(findmnt -no SOURCE / 2>/dev/null)
    if [[ -n "$root_device" ]]; then
        # Skip validation for airootfs (ArchISO live environment)
        if [[ "$root_device" == *"airootfs"* ]]; then
            debug "Running in ArchISO, skipping root disk validation"
            return 0
        fi
        
        local root_disk
        # Use lsblk with error suppression
        root_disk=$(lsblk -no PKNAME "$root_device" 2>/dev/null | head -n1 || true)
        # Filter out any error messages
        root_disk=$(echo "$root_disk" | grep -v "No such file" || true)
        if [[ -n "$root_disk" && "$root_disk" != "" ]]; then
            root_disk="/dev/$root_disk"
            if [[ "$disk" == "$root_disk" ]]; then
                error "Cannot install to the current system disk: $disk"
            fi
        fi
    fi
    
    debug "validate_disk passed for: $disk"
}

# ============================================
# CONFIRMATION
# ============================================
confirm_strict() {
    local target="$1"
    debug "confirm_strict called with: $target"
    warn "THIS WILL ERASE ALL DATA ON ${target}!"
    
    # Check if --yes flag was passed (for automation)
    if [[ "${AUTO_CONFIRM:-0}" == "1" ]]; then
        info "Auto-confirming (AUTO_CONFIRM=1)"
        return 0
    fi
    
    # Check if running in interactive mode
    if [[ ! -t 0 ]]; then
        error "Non-interactive mode detected. Use --yes flag to auto-confirm."
    fi
    
    echo -n "Type 'ERASE' to continue: "
    read -r confirmation
    if [[ "$confirmation" != "ERASE" ]]; then
        error "Aborted by user."
    fi
    debug "confirm_strict passed for: $target"
}

# ============================================
# PARTITION HANDLING
# ============================================
get_partitions() {
    local disk="$1"
    local boot_mode="${2:-uefi}"
    debug "get_partitions called with: $disk, boot_mode: $boot_mode"
    
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
    
    debug "get_partitions: BOOT_PART=$BOOT_PART, ROOT_PART=$ROOT_PART"
}

# ============================================
# PROFILE VALIDATION
# ============================================
validate_profile() {
    local profile="$1"
    local script_dir="$2"
    debug "validate_profile called with: $profile, script_dir: $script_dir"
    
    if [[ "$profile" == "none" ]]; then
        return 0
    fi
    
    if [[ ! -f "${script_dir}/profiles/${profile}.sh" ]]; then
        error "Profile '${profile}' not found in ${script_dir}/profiles/"
    fi
    
    info "Profile '${profile}' validated"
}

# Check if profile is compatible with current distro
validate_profile_distro() {
    local profile="$1"
    local script_dir="$2"
    local distro="$3"
    debug "validate_profile_distro called with: $profile, $script_dir, $distro"
    
    # For now, all profiles are Arch-only
    if [[ "$distro" != "arch" ]]; then
        warn "Profile '$profile' is designed for Arch Linux"
    fi
}

# ============================================
# CLEANUP
# ============================================
cleanup_on_error() {
    debug "cleanup_on_error called"
    warn "Cleaning up after error..."
    if mountpoint -q /mnt; then
        umount -R /mnt 2>/dev/null || true
    fi
    swapoff -a 2>/dev/null || true
}

# Set trap for cleanup
trap cleanup_on_error ERR

# ============================================
# HELPER FUNCTIONS
# ============================================
# Check if package is installed
package_installed() {
    local pkg="$1"
    debug "package_installed called with: $pkg"
    if command -v pacman >/dev/null 2>&1; then
        pacman -Q "$pkg" &>/dev/null
    elif command -v apt >/dev/null 2>&1; then
        dpkg -l "$pkg" &>/dev/null
    else
        return 1
    fi
}

# Get available disk space in GB
get_available_space() {
    local mountpoint="$1"
    debug "get_available_space called with: $mountpoint"
    df -BG "$mountpoint" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//'
}
