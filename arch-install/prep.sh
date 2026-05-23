#!/bin/bash
set -uo pipefail

# Enable debug mode if DEBUG=1
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x
fi

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
    echo "ERROR: Dependencies not found. Please use the bootstrap script for remote execution:"
    echo "curl -L https://raw.githubusercontent.com/kasper-studios/kzsh/main/arch-install/bootstrap.sh | bash"
    exit 1
fi

source "${SCRIPT_DIR}/lib/common.sh"

info "prep.sh started"

# ============================================
# DISTRIBUTION DETECTION
# ============================================
KZSH_DISTRO=$(detect_distro)
info "Detected distribution: $KZSH_DISTRO"

info "Checking if distribution is supported..."
if ! is_distro_supported "$KZSH_DISTRO"; then
    error "Unsupported distribution: $KZSH_DISTRO. Only Arch Linux-based distros are supported."
fi

info "Distribution validation passed"

# ============================================
# INTERNET CHECK
# ============================================
check_internet

# ============================================
# DEFAULT VALUES
# ============================================
DISK=""
HOSTNAME="ponosik"
USERNAME="kasperenok"
PROFILE="desktop-sddm-niri"
SWAP_SIZE=""
FILESYSTEM="btrfs"
BOOTLOADER="auto"
INSTALL_KZSH="yes"
AUTO_CONFIRM="0"

# ============================================
# PARSE ARGUMENTS
# ============================================
while [[ $# -gt 0 ]]; do
    case $1 in
        --disk|-disk) DISK="$2"; shift 2 ;;
        --hostname|-hostname) HOSTNAME="$2"; shift 2 ;;
        --user|-user) USERNAME="$2"; shift 2 ;;
        --profile|-profile) PROFILE="$2"; shift 2 ;;
        --swap|-swap) SWAP_SIZE="$2"; shift 2 ;;
        --fs|-fs) FILESYSTEM="$2"; shift 2 ;;
        --bootloader|-bootloader) BOOTLOADER="$2"; shift 2 ;;
        --kzsh|-kzsh) INSTALL_KZSH="$2"; shift 2 ;;
        --yes|-yes) AUTO_CONFIRM="1"; shift ;;
        --debug|-debug) DEBUG=1; shift ;;
        *) 
            # If it starts with -, it's an unknown option
            if [[ "$1" == -* ]]; then
                error "Unknown option: $1"
            fi
            shift
            ;;
    esac
done

info "Arguments parsed: DISK=$DISK, HOSTNAME=$HOSTNAME, USERNAME=$USERNAME, PROFILE=$PROFILE"

# ============================================
# INTERACTIVE MODE
# ============================================
if [[ -z "$DISK" ]]; then
    info "Entering interactive mode..."
    info "No disk specified, interactive mode required."
    info ""
    info "Please run the installer with parameters instead:"
    info "  curl -L https://raw.githubusercontent.com/kasper-studios/kzsh/main/arch-install/bootstrap.sh | bash -s -- \\"
    info "    --disk /dev/sda \\"
    info "    --hostname myhostname \\"
    info "    --user myuser \\"
    info "    --profile desktop-sddm-niri \\"
    info "    --fs btrfs \\"
    info "    --swap 4096 \\"
    info "    --kzsh yes"
    info ""
    info "Available profiles: minimal, base, dev, desktop-gnome, desktop-kde, desktop-sddm-niri"
    info "Available filesystems: btrfs, ext4"
    info ""
    error "Interactive mode is not supported when running via curl pipe. Please use command-line arguments."
fi

info "Configuration: DISK=$DISK, HOSTNAME=$HOSTNAME, USERNAME=$USERNAME, PROFILE=$PROFILE"

# ============================================
# VALIDATION
# ============================================
info "Validating disk: $DISK"
validate_disk "$DISK"
info "Disk validation passed"
check_disk_size "$DISK"
info "Disk size check passed"

# Validate filesystem choice
if [[ "$FILESYSTEM" != "btrfs" && "$FILESYSTEM" != "ext4" ]]; then
    error "Invalid filesystem: $FILESYSTEM (must be btrfs or ext4)"
fi

# Validate profile
validate_profile "$PROFILE" "$SCRIPT_DIR"
validate_profile_distro "$PROFILE" "$SCRIPT_DIR" "$KZSH_DISTRO"

# Normalize KZSH installation option
INSTALL_KZSH=$(echo "$INSTALL_KZSH" | tr '[:upper:]' '[:lower:]')
if [[ "$INSTALL_KZSH" =~ ^(y|yes|1|true)$ ]]; then
    INSTALL_KZSH="yes"
elif [[ "$INSTALL_KZSH" =~ ^(n|no|0|false)$ ]]; then
    INSTALL_KZSH="no"
else
    warn "Invalid KZSH option: $INSTALL_KZSH, defaulting to 'yes'"
    INSTALL_KZSH="yes"
fi

# Detect boot mode first
info "Detecting boot mode..."
BOOT_MODE=$(detect_boot_mode)
info "Boot mode: $BOOT_MODE"
check_boot_mode

# Determine bootloader based on boot mode
if [[ "$BOOTLOADER" == "auto" ]]; then
    if [[ "$BOOT_MODE" == "uefi" ]]; then
        BOOTLOADER="grub"
    else
        BOOTLOADER="grub"
    fi
fi

info "Bootloader: $BOOTLOADER"

# ============================================
# CONFIGURATION SUMMARY
# ============================================
info "Configuration:"
info "  Distribution: $KZSH_DISTRO"
info "  Disk: $DISK"
info "  Boot Mode: $BOOT_MODE"
info "  Bootloader: $BOOTLOADER"
info "  Filesystem: $FILESYSTEM"
info "  Hostname: $HOSTNAME"
info "  Username: $USERNAME"
info "  Profile: $PROFILE"
[[ -n "$SWAP_SIZE" ]] && info "  Swap: ${SWAP_SIZE}MB"
info "  Install KZSH: $INSTALL_KZSH"

info "Starting confirmation prompt..."
export AUTO_CONFIRM
confirm_strict "$DISK"
info "Confirmation passed"

# Enable cleanup on error after user confirmation
export CLEANUP_ENABLED=1

info "Partitioning $DISK..."

# Unmount any partitions on the disk
info "Unmounting any existing partitions on $DISK..."
for part in $(lsblk -lno NAME "$DISK" 2>/dev/null | grep -v "^${DISK##*/}$" || true); do
    if mountpoint -q "/dev/$part" 2>/dev/null || mount | grep -q "^/dev/$part"; then
        info "Unmounting /dev/$part..."
        umount -f "/dev/$part" 2>/dev/null || true
    fi
done

# Disable any swap on the disk
info "Disabling swap on $DISK..."
for part in $(lsblk -lno NAME "$DISK" 2>/dev/null | grep -v "^${DISK##*/}$" || true); do
    swapoff "/dev/$part" 2>/dev/null || true
done

# Wipe filesystem signatures and partition table
info "Wiping filesystem signatures and partition table..."
wipefs -af "$DISK" 2>/dev/null || true
dd if=/dev/zero of="$DISK" bs=512 count=1 conv=notrunc 2>/dev/null || true
sync

# Wait for kernel to update
sleep 2

if [[ "$BOOT_MODE" == "uefi" ]]; then
    # UEFI: EFI System Partition + Root
    info "Creating GPT label and partitions for UEFI..."
    parted -s "$DISK" mklabel gpt || error "Failed to create GPT label"
    parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB || error "Failed to create ESP partition"
    parted -s "$DISK" set 1 esp on || error "Failed to set ESP flag"
    parted -s "$DISK" mkpart ROOT "$FILESYSTEM" 513MiB 100% || error "Failed to create root partition"
    
    # Wait for kernel to recognize partitions
    sync
    partprobe "$DISK" 2>/dev/null || true
    sleep 2
    
    # Get partition names
    get_partitions "$DISK" "uefi"
    
    # Verify partitions exist
    if [[ ! -b "$BOOT_PART" ]]; then
        error "Boot partition $BOOT_PART was not created"
    fi
    if [[ ! -b "$ROOT_PART" ]]; then
        error "Root partition $ROOT_PART was not created"
    fi
    
    info "Formatting EFI partition..."
    mkfs.fat -F32 "$BOOT_PART" || error "Failed to format EFI partition"
else
    # BIOS: BIOS boot partition + Root partition
    info "Creating GPT label and partitions for BIOS..."
    parted -s "$DISK" mklabel gpt || error "Failed to create GPT label"
    parted -s "$DISK" mkpart BIOS 1MiB 2MiB || error "Failed to create BIOS boot partition"
    parted -s "$DISK" set 1 bios_grub on || error "Failed to set bios_grub flag"
    parted -s "$DISK" mkpart ROOT "$FILESYSTEM" 2MiB 100% || error "Failed to create root partition"
    
    # Wait for kernel to recognize partitions
    sync
    partprobe "$DISK" 2>/dev/null || true
    sleep 2
    
    # Get partition names
    get_partitions "$DISK" "bios"
    
    # Verify root partition exists
    if [[ ! -b "$ROOT_PART" ]]; then
        error "Root partition $ROOT_PART was not created"
    fi
fi

info "Partitioning completed"
info "Boot partition: ${BOOT_PART:-none}"
info "Root partition: $ROOT_PART"

info "Formatting root partition with $FILESYSTEM..."
if [[ "$FILESYSTEM" == "btrfs" ]]; then
    info "Creating BTRFS filesystem..."
    if ! mkfs.btrfs -f "$ROOT_PART" 2>&1; then
        error "Failed to create BTRFS filesystem on $ROOT_PART. The partition may be too small (minimum ~109MB required for BTRFS). Try using ext4 instead with --fs ext4"
    fi
else
    info "Creating ext4 filesystem..."
    mkfs.ext4 -F "$ROOT_PART"
fi
info "Root partition formatted"

# Use /install-root instead of /mnt to avoid conflict with ArchISO squashfs
INSTALL_ROOT="/install-root"

validate_and_prepare_install_root "$INSTALL_ROOT"



if [[ "$FILESYSTEM" == "btrfs" ]]; then
    info "Mounting root partition temporarily for BTRFS subvolume creation..."
    mount "$ROOT_PART" "$INSTALL_ROOT" || error "Failed to mount root partition"
    
    info "Creating BTRFS subvolumes..."
    btrfs subvolume create "$INSTALL_ROOT/@" || error "Failed to create @ subvolume"
    btrfs subvolume create "$INSTALL_ROOT/@home" || error "Failed to create @home subvolume"
    btrfs subvolume create "$INSTALL_ROOT/@log" || error "Failed to create @log subvolume"
    btrfs subvolume create "$INSTALL_ROOT/@pkg" || error "Failed to create @pkg subvolume"
    if [[ -n "$SWAP_SIZE" ]]; then
        btrfs subvolume create "$INSTALL_ROOT/@swap" || error "Failed to create @swap subvolume"
    fi

    info "Unmounting and remounting with subvolumes..."
    umount "$INSTALL_ROOT" || error "Failed to unmount root partition"
    
    info "Mounting @ subvolume..."
    mount -o subvol=@,compress=zstd,noatime "$ROOT_PART" "$INSTALL_ROOT" || error "Failed to mount @ subvolume"
    
    info "Creating mount point directories..."
    mkdir -p "$INSTALL_ROOT/home" || error "Failed to create /home directory"
    mkdir -p "$INSTALL_ROOT/var/log" || error "Failed to create /var/log directory"
    mkdir -p "$INSTALL_ROOT/var/cache/pacman/pkg" || error "Failed to create /var/cache/pacman/pkg directory"
    
    info "Mounting subvolumes..."
    mount -o subvol=@home,compress=zstd,noatime "$ROOT_PART" "$INSTALL_ROOT/home" || error "Failed to mount @home subvolume"
    mount -o subvol=@log,compress=zstd,noatime "$ROOT_PART" "$INSTALL_ROOT/var/log" || error "Failed to mount @log subvolume"
    mount -o subvol=@pkg,compress=zstd,noatime "$ROOT_PART" "$INSTALL_ROOT/var/cache/pacman/pkg" || error "Failed to mount @pkg subvolume"

    if [[ -n "$SWAP_SIZE" ]]; then
        info "Setting up swap subvolume..."
        mkdir -p "$INSTALL_ROOT/swap" || error "Failed to create /swap directory"
        mount -o subvol=@swap,noatime "$ROOT_PART" "$INSTALL_ROOT/swap" || error "Failed to mount @swap subvolume"
        
        info "Creating swap file on BTRFS..."
        # BTRFS swap file creation (requires special handling)
        truncate -s 0 "$INSTALL_ROOT/swap/swapfile" || error "Failed to create swap file"
        chattr +C "$INSTALL_ROOT/swap/swapfile" 2>/dev/null || warn "Could not set NOCOW attribute (chattr +C)"
        dd if=/dev/zero of="$INSTALL_ROOT/swap/swapfile" bs=1M count="$SWAP_SIZE" status=progress || error "Failed to allocate swap file"
        chmod 600 "$INSTALL_ROOT/swap/swapfile" || error "Failed to set swap file permissions"
        mkswap "$INSTALL_ROOT/swap/swapfile" || error "Failed to format swap file"
        swapon "$INSTALL_ROOT/swap/swapfile" || error "Failed to enable swap file"
        info "Swap file created and enabled"
    fi
else
    info "Mounting ext4 filesystem..."
    mount "$ROOT_PART" "$INSTALL_ROOT" || error "Failed to mount root partition to $INSTALL_ROOT"
    mkdir -p "$INSTALL_ROOT/{home,var/log,var/cache/pacman/pkg}"
    
    if [[ -n "$SWAP_SIZE" ]]; then
        info "Creating swap file..."
        dd if=/dev/zero of="$INSTALL_ROOT/swapfile" bs=1M count="$SWAP_SIZE" status=progress
        chmod 600 "$INSTALL_ROOT/swapfile"
        mkswap "$INSTALL_ROOT/swapfile"
        swapon "$INSTALL_ROOT/swapfile"
    fi
fi

info "Filesystem mounted"

# Mount boot partition for UEFI
if [[ "$BOOT_MODE" == "uefi" && -n "$BOOT_PART" ]]; then
    info "Mounting EFI partition..."
    mkdir -p "$INSTALL_ROOT/boot"
    mount "$BOOT_PART" "$INSTALL_ROOT/boot" || error "Failed to mount EFI partition to $INSTALL_ROOT/boot"
fi

info "Boot partition mounted"

info "Installing base system (pacstrap)..."
# Basic packages plus what's needed for the next stage
BASE_PACKAGES="base linux linux-firmware vim networkmanager git curl zsh sudo"

# Add CPU microcode based on detected CPU
if grep -q "GenuineIntel" /proc/cpuinfo; then
    BASE_PACKAGES="$BASE_PACKAGES intel-ucode"
    info "Detected Intel CPU, adding intel-ucode"
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    BASE_PACKAGES="$BASE_PACKAGES amd-ucode"
    info "Detected AMD CPU, adding amd-ucode"
fi

# Add filesystem-specific tools
if [[ "$FILESYSTEM" == "btrfs" ]]; then
    BASE_PACKAGES="$BASE_PACKAGES btrfs-progs"
else
    BASE_PACKAGES="$BASE_PACKAGES e2fsprogs"
fi

# Add bootloader packages
if [[ "$BOOTLOADER" == "grub" ]]; then
    BASE_PACKAGES="$BASE_PACKAGES grub"
    if [[ "$BOOT_MODE" == "uefi" ]]; then
        BASE_PACKAGES="$BASE_PACKAGES efibootmgr"
    fi
fi

info "Base packages: $BASE_PACKAGES"
info "Running pacstrap (this may take several minutes)..."
if ! pacstrap -K "$INSTALL_ROOT" $BASE_PACKAGES; then
    error "Pacstrap failed. Check your internet connection and try again."
fi
info "Pacstrap completed successfully"

info "Generating fstab..."
genfstab -U "$INSTALL_ROOT" >> "$INSTALL_ROOT/etc/fstab"
info "Fstab generated"

# Copy the installation folder to the new system for the second stage
info "Copying installation folder to $INSTALL_ROOT/root/arch-install..."
cp -r "${SCRIPT_DIR}" "$INSTALL_ROOT/root/arch-install"
chmod +x "$INSTALL_ROOT/root/arch-install/post.sh"
chmod +x "$INSTALL_ROOT/root/arch-install/prep.sh"
chmod +x "$INSTALL_ROOT/root/arch-install/bootstrap.sh"
info "Installation folder copied"

# Save installation metadata for post.sh
info "Saving installation metadata..."
cat > "$INSTALL_ROOT/root/arch-install/.install-meta" << EOF
BOOT_MODE=$BOOT_MODE
BOOTLOADER=$BOOTLOADER
FILESYSTEM=$FILESYSTEM
DISK=$DISK
INSTALL_KZSH=$INSTALL_KZSH
EOF
info "Installation metadata saved"

success "Stage 1 (Prep) complete."
info "Now run: arch-chroot $INSTALL_ROOT /root/arch-install/post.sh --hostname $HOSTNAME --user $USERNAME --profile $PROFILE"

info "prep.sh completed successfully"
