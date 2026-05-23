#!/usr/bin/env bash
set -uo pipefail

# Enable debug mode if DEBUG=1
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x
fi

# Source common functions
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

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
    info "Available disks:"
    # Get list of block devices, filter out loops and show only disks
    lsblk -d -o NAME,SIZE,MODEL,TYPE 2>/dev/null | awk 'NR==1 || /disk/' || echo "No disks found"
    echo
    read -rp "Target disk (example: /dev/sda): " DISK
    read -rp "Hostname [$HOSTNAME]: " input_host
    HOSTNAME="${input_host:-$HOSTNAME}"
    read -rp "Username [$USERNAME]: " input_user
    USERNAME="${input_user:-$USERNAME}"
    read -rp "Filesystem (btrfs/ext4) [$FILESYSTEM]: " input_fs
    FILESYSTEM="${input_fs:-$FILESYSTEM}"
    read -rp "Swap size in MB (leave empty for none): " SWAP_SIZE
    read -rp "Install KZSH after setup? [Y/n]: " input_kzsh
    INSTALL_KZSH="${input_kzsh:-yes}"
fi

info "Interactive mode completed: DISK=$DISK"

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

info "Partitioning $DISK..."

# Check if disk has existing partitions and remove them
if lsblk -no NAME "$DISK" | grep -q "^${DISK##*/}"; then
    info "Existing partitions found on $DISK, removing..."
    # Remove all partitions from the disk
    for part in $(lsblk -no NAME "$DISK"); do
        if [[ "$part" != "${DISK##*/}" ]]; then
            info "Removing partition: /dev/$part"
            rm -f "/dev/$part" 2>/dev/null || true
        fi
    done
    # Wipe partition table
    wipefs -a "$DISK" 2>/dev/null || true
fi

if [[ "$BOOT_MODE" == "uefi" ]]; then
    # UEFI: EFI System Partition + Root
    info "Creating GPT label and partitions for UEFI..."
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart ROOT "$FILESYSTEM" 513MiB 100%
    get_partitions "$DISK" "uefi"
    
    info "Formatting EFI partition..."
    mkfs.fat -F32 "$BOOT_PART"
else
    # BIOS: Single root partition with BIOS boot for GRUB
    info "Creating GPT label and partitions for BIOS..."
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart BIOS 1MiB 2MiB
    parted -s "$DISK" set 1 bios_grub on
    parted -s "$DISK" mkpart ROOT "$FILESYSTEM" 2MiB 100%
    get_partitions "$DISK" "bios"
fi

info "Partitioning completed"

info "Formatting root partition with $FILESYSTEM..."
if [[ "$FILESYSTEM" == "btrfs" ]]; then
    info "Creating BTRFS filesystem..."
    mkfs.btrfs -f "$ROOT_PART"
else
    info "Creating ext4 filesystem..."
    mkfs.ext4 -F "$ROOT_PART"
fi
info "Root partition formatted"

# Use /install-root instead of /mnt to avoid conflict with ArchISO squashfs
INSTALL_ROOT="/install-root"

# Clean up install root if it exists
if mountpoint -q "$INSTALL_ROOT" 2>/dev/null; then
    info "Unmounting $INSTALL_ROOT..."
    umount "$INSTALL_ROOT" 2>/dev/null || true
fi

# Remove install root directory if it exists
if [[ -d "$INSTALL_ROOT" && ! -L "$INSTALL_ROOT" ]]; then
    info "Removing $INSTALL_ROOT directory..."
    rmdir "$INSTALL_ROOT" 2>/dev/null || rm -rf "$INSTALL_ROOT" 2>/dev/null || true
fi

# Create fresh install root directory
mkdir -p "$INSTALL_ROOT"

# Mount the root partition to install root
info "Mounting root partition to $INSTALL_ROOT..."
mount "$ROOT_PART" "$INSTALL_ROOT"
info "Root partition mounted to $INSTALL_ROOT"

if [[ "$FILESYSTEM" == "btrfs" ]]; then
    info "Creating BTRFS subvolumes..."
    btrfs subvolume create "$INSTALL_ROOT/@"
    btrfs subvolume create "$INSTALL_ROOT/@home"
    btrfs subvolume create "$INSTALL_ROOT/@log"
    btrfs subvolume create "$INSTALL_ROOT/@pkg"
    if [[ -n "$SWAP_SIZE" ]]; then
        btrfs subvolume create "$INSTALL_ROOT/@swap"
    fi

    info "Unmounting and remounting with subvolumes..."
    umount "$INSTALL_ROOT"
    
    mount -o subvol=@,compress=zstd,noatime "$ROOT_PART" "$INSTALL_ROOT"
    mkdir -p "$INSTALL_ROOT/{home,var/log,var/cache/pacman/pkg}"
    mount -o subvol=@home,compress=zstd,noatime "$ROOT_PART" "$INSTALL_ROOT/home"
    mount -o subvol=@log,compress=zstd,noatime "$ROOT_PART" "$INSTALL_ROOT/var/log"
    mount -o subvol=@pkg,compress=zstd,noatime "$ROOT_PART" "$INSTALL_ROOT/var/cache/pacman/pkg"

    if [[ -n "$SWAP_SIZE" ]]; then
        mkdir -p "$INSTALL_ROOT/swap"
        mount -o subvol=@swap,noatime "$ROOT_PART" "$INSTALL_ROOT/swap"
        # Create swap file without chattr (BTRFS doesn't support it)
        truncate -s 0 "$INSTALL_ROOT/swap/swapfile"
        dd if=/dev/zero of="$INSTALL_ROOT/swap/swapfile" bs=1M count="$SWAP_SIZE" status=progress
        chmod 600 "$INSTALL_ROOT/swap/swapfile"
        mkswap "$INSTALL_ROOT/swap/swapfile"
        swapon "$INSTALL_ROOT/swap/swapfile"
    fi
else
    info "Mounting ext4 filesystem..."
    mount "$ROOT_PART" "$INSTALL_ROOT"
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
    mount "$BOOT_PART" "$INSTALL_ROOT/boot"
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
info "Running pacstrap..."
pacstrap "$INSTALL_ROOT" $BASE_PACKAGES
info "Pacstrap completed"

info "Generating fstab..."
genfstab -U "$INSTALL_ROOT" >> "$INSTALL_ROOT/etc/fstab"
info "Fstab generated"

# Copy the installation folder to the new system for the second stage
info "Copying installation folder to $INSTALL_ROOT/root/arch-install..."
cp -r "${SCRIPT_DIR}" "$INSTALL_ROOT/root/arch-install"
info "Installation folder copied"

# Save installation metadata for post.sh
info "Saving installation metadata..."
cat > "$INSTALL_ROOT/root/arch-install/.install-meta << EOF
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
