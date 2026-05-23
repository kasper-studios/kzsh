#!/bin/bash
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
        local detected_id="$ID"
        debug "Detected distro: $detected_id"
        echo "$detected_id"
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
    if [[ ! -t 0 ]] && [[ ! -e /dev/tty ]]; then
        error "Non-interactive mode detected and no TTY available. Use --yes flag to auto-confirm."
    fi
    
    # Use /dev/tty for input when stdin is redirected (e.g., piped from curl)
    if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
        echo -n "Type 'ERASE' to continue: " > /dev/tty
        read -r confirmation < /dev/tty
    else
        echo -n "Type 'ERASE' to continue: "
        read -r confirmation
    fi
    
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
            # BIOS: partition 1 is BIOS boot (1MB), partition 2 is root
            ROOT_PART="${disk}p2"
            BOOT_PART=""
        fi
    else
        if [[ "$boot_mode" == "uefi" ]]; then
            BOOT_PART="${disk}1"
            ROOT_PART="${disk}2"
        else
            # BIOS: partition 1 is BIOS boot (1MB), partition 2 is root
            ROOT_PART="${disk}2"
            BOOT_PART=""
        fi
    fi
    
    debug "get_partitions: BOOT_PART=$BOOT_PART, ROOT_PART=$ROOT_PART"
    
    # Export variables so they're available in the calling script
    export BOOT_PART
    export ROOT_PART
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
    
    # Turn off swap first
    swapoff -a 2>/dev/null || true
    
    # Function to unmount a directory and all its nested mounts
    unmount_recursive() {
        local mount_point="$1"
        
        if [[ ! -d "$mount_point" ]]; then
            debug "Mount point $mount_point does not exist, skipping"
            return 0
        fi
        
        if ! mountpoint -q "$mount_point" 2>/dev/null; then
            debug "$mount_point is not a mount point, skipping"
            return 0
        fi
        
        debug "Unmounting $mount_point and nested mounts..."
        
        # Get all mount points under the target, sorted by depth (deepest first)
        local mounts
        mounts=$(findmnt -R -n -o TARGET "$mount_point" 2>/dev/null | tac || true)
        
        if [[ -z "$mounts" ]]; then
            debug "No mounts found under $mount_point"
            return 0
        fi
        
        # Unmount each mount point
        while IFS= read -r mount; do
            if [[ -n "$mount" ]] && mountpoint -q "$mount" 2>/dev/null; then
                debug "Unmounting: $mount"
                umount "$mount" 2>/dev/null || umount -l "$mount" 2>/dev/null || true
            fi
        done <<< "$mounts"
    }
    
    # Try to unmount /install-root (primary mount point used by the script)
    unmount_recursive "/install-root"
    
    # Also try /mnt for compatibility
    unmount_recursive "/mnt"
    
    debug "cleanup_on_error completed"
}

# Set trap for cleanup

# ============================================
# MOUNT POINT VALIDATION AND CLEANUP
# ============================================

# Check if a path or any of its subdirectories are mounted
check_mounts_under_path() {
    local target_path=$1
    debug check_mounts_under_path called with: "${target_path}"
    
    # Normalize path (remove trailing slash)
    target_path=${target_path%/}
    
    # Get all mount points that start with target_path
    local mounted_paths
    mounted_paths=$(findmnt -n -o TARGET 2>/dev/null | grep "^${target_path}" | sort -r)
    
    if [[ -n "$mounted_paths" ]]; then
        debug "Found mounts under ${target_path}:"
        printf '%s\n' "$mounted_paths" | while read -r mp; do
            debug " - ${mp}"
        done
        return 0  # Mounts found
    else
        debug "No mounts found under ${target_path}"
        return 1  # No mounts found
    fi
}

# Get list of all mount points under a path, sorted by depth (deepest first)
get_mounts_under_path() {
    local target_path=$1
    debug get_mounts_under_path called with: "${target_path}"
    
    # Normalize path (remove trailing slash)
    target_path=${target_path%/}
    
    # Get all mount points under target_path, sort by depth (deepest first)
    findmnt -R -n -o TARGET "$target_path" 2>/dev/null | tac
}

# Unmount all mounts under a path (deepest first to avoid busy errors)
unmount_all_under_path() {
    local target_path=$1
    local force=${2:-no}
    debug unmount_all_under_path called with: "$target_path", force: "$force"
    
    info "Checking for existing mounts under $target_path..."
    
    local mounted_paths
    mounted_paths=$(get_mounts_under_path "$target_path")
    
    if [[ -z "$mounted_paths" ]]; then
        debug "No mounts found under $target_path"
        return 0
    fi
    
    info "Found existing mounts under $target_path, unmounting..."
    
    # Disable swap files under target path first
    while read -r mp; do
        if [[ -n "$mp" ]]; then
            # Check for swap files in this mount
            local swap_files
            swap_files=$(swapon --show=NAME --noheadings 2>/dev/null | grep "^${mp}/" || true)
            if [[ -n "$swap_files" ]]; then
                while read -r swap_file; do
                    if [[ -n "$swap_file" ]]; then
                        info "Disabling swap: $swap_file"
                        swapoff "$swap_file" 2>/dev/null || warn "Failed to disable swap: $swap_file"
                    fi
                done <<< "$swap_files"
            fi
        fi
    done <<< "$mounted_paths"
    
    # Unmount in reverse order (deepest first)
    local unmount_failed=0
    while read -r mp; do
        if [[ -n "$mp" ]]; then
            info "Unmounting: $mp"
            
            # Try normal unmount first
            if umount "$mp" 2>/dev/null; then
                success "Unmounted: $mp"
            else
                warn "Failed to unmount $mp, trying lazy unmount..."
                if umount -l "$mp" 2>/dev/null; then
                    success "Lazy unmounted: $mp"
                else
                    if [[ "$force" == yes ]]; then
                        warn "Forcing unmount of $mp..."
                        umount -f "$mp" 2>/dev/null || warn "Force unmount failed: $mp"
                    else
                        error "Failed to unmount $mp. Use force mode or check for processes using this mount."
                    fi
                    unmount_failed=1
                fi
            fi
        fi
    done <<< "$mounted_paths"
    
    if [[ $unmount_failed -eq 1 ]]; then
        return 1
    fi
    
    success "All mounts under $target_path have been unmounted"
    return 0
}

# Validate and prepare install root directory
validate_and_prepare_install_root() {
    local install_root=$1
    debug validate_and_prepare_install_root called with: $install_root
    
    info "Validating install root: $install_root"
    
    # Check if install_root or any subdirectories are mounted
    if check_mounts_under_path "$install_root"; then
        warn "Found existing mounts under $install_root"
        
        # List all mounts for user visibility
        info "Existing mounts:"
        get_mounts_under_path "$install_root" | while read -r mp; do
            if [[ -n "$mp" ]]; then
                local mount_info
                mount_info=$(findmnt -n -o SOURCE,FSTYPE,OPTIONS "$mp" 2>/dev/null | head -n1)
                info "  $mp: $mount_info"
            fi
        done
        
        # Unmount all existing mounts
        unmount_all_under_path "$install_root" no
    fi
    
    # Verify no mounts remain
    if check_mounts_under_path "$install_root"; then
        error "Failed to unmount all mounts under $install_root"
    fi
    
    # Clean up the directory
    if [[ -e "$install_root" ]]; then
        if [[ -L "$install_root" ]]; then
            info "Removing symlink: $install_root"
            rm -f "$install_root"
        elif [[ -d "$install_root" ]]; then
            info "Cleaning install root directory: $install_root"
            # Check if directory is empty
            if [[ -n $(ls -A "$install_root" 2>/dev/null) ]]; then
                warn "Directory $install_root is not empty, removing contents..."
                rm -rf "${install_root:?}"/* 2>/dev/null || true
                rm -rf "${install_root:?}"/.[!.]* 2>/dev/null || true
                rm -rf "${install_root:?}"/..?* 2>/dev/null || true
            fi
            # Try to remove directory
            if ! rmdir "$install_root" 2>/dev/null; then
                warn "Could not remove $install_root, forcing removal..."
                rm -rf "$install_root" 2>/dev/null || true
            fi
        elif [[ -f "$install_root" ]]; then
            warn "$install_root is a file, removing..."
            rm -f "$install_root"
        fi
    fi
    
    # Create fresh directory
    info "Creating fresh install root directory: $install_root"
    mkdir -p "$install_root"
    
    # Verify directory was created and is empty
    if [[ ! -d "$install_root" ]]; then
        error "Failed to create install root directory: $install_root"
    fi
    
    if [[ -n $(ls -A "$install_root" 2>/dev/null) ]]; then
        error "Install root directory is not empty after cleanup: $install_root"
    fi
    
    success "Install root validated and prepared: $install_root"
}
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
