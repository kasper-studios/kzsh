#!/usr/bin/env bash
set -euo pipefail

# Source common functions
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [[ ! -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
    echo "ERROR: Dependencies not found. Please use the bootstrap script for remote execution:"
    echo "curl -L https://raw.githubusercontent.com/kasper-studios/kzsh/main/arch-install/bootstrap.sh | bash"
    exit 1
fi

source "${SCRIPT_DIR}/lib/common.sh"

# ============================================
# DISTRIBUTION DETECTION
# ============================================
KZSH_DISTRO=$(detect_distro)
info "Detected distribution: $KZSH_DISTRO"

if ! is_distro_supported "$KZSH_DISTRO"; then
    error "Unsupported distribution: $KZSH_DISTRO. Only Arch Linux-based distros are supported."
fi

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

# ============================================
# INTERACTIVE MODE
# ============================================
if [[ -z "$DISK" ]]; then
    info "Available disks:"
    lsblk -d -o NAME,SIZE,MODEL,TYPE 2>/dev/null | grep -E "disk|loop" || echo "No disks found"
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

# ============================================
# VALIDATION
# ============================================
validate_disk "$DISK"
check_disk_size "$DISK"

# Validate filesystem choice
if [[ "$FILESYSTEM" != "btrfs" && "$FILESYSTEM" != "ext4" ]]; then
    error "Invalid filesystem: $FILESYSTEM (must be btrfs or ext4)"
fi

# Validate profile
validate_profile "$PROFILE" "$SCRIPT_DIR"
validate_profile_distro "$PROFILE" "$SCRIPT_DIR" "$KZSH_DISTRO"

# Detect boot mode first
BOOT_MODE=$(detect_boot_mode)
check_boot_mode

# Determine bootloader based on boot mode
if [[ "$BOOTLOADER" == "auto" ]]; then
    if [[ "$BOOT_MODE" == "uefi" ]]; then
        BOOTLOADER="grub"
    else
        BOOTLOADER="grub"
    fi
fi

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

confirm_strict "$DISK"

info "Partitioning $DISK..."

if [[ "$BOOT_MODE" == "uefi" ]]; then
    # UEFI: EFI System Partition + Root
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart ROOT "$FILESYSTEM" 513MiB 100%
    get_partitions "$DISK" "uefi"
    
    info "Formatting EFI partition..."
    mkfs.fat -F32 "$BOOT_PART"
else
    # BIOS: Single root partition with BIOS boot for GRUB
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart BIOS 1MiB 2MiB
    parted -s "$DISK" set 1 bios_grub on
    parted -s "$DISK" mkpart ROOT "$FILESYSTEM" 2MiB 100%
    get_partitions "$DISK" "bios"
fi

info "Formatting root partition with $FILESYSTEM..."
if [[ "$FILESYSTEM" == "btrfs" ]]; then
    mkfs.btrfs -f "$ROOT_PART"
else
    mkfs.ext4 -F "$ROOT_PART"
fi

if [[ "$FILESYSTEM" == "btrfs" ]]; then
    info "Creating BTRFS subvolumes..."
    mount "$ROOT_PART" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@log
    btrfs subvolume create /mnt/@pkg
    if [[ -n "$SWAP_SIZE" ]]; then
        btrfs subvolume create /mnt/@swap
    fi
    umount /mnt

    info "Mounting BTRFS subvolumes..."
    mount -o subvol=@,compress=zstd,noatime "$ROOT_PART" /mnt
    mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg}
    mount -o subvol=@home,compress=zstd,noatime "$ROOT_PART" /mnt/home
    mount -o subvol=@log,compress=zstd,noatime "$ROOT_PART" /mnt/var/log
    mount -o subvol=@pkg,compress=zstd,noatime "$ROOT_PART" /mnt/var/cache/pacman/pkg

    if [[ -n "$SWAP_SIZE" ]]; then
        mkdir -p /mnt/swap
        mount -o subvol=@swap,noatime "$ROOT_PART" /mnt/swap
        truncate -s 0 /mnt/swap/swapfile
        chattr +C /mnt/swap/swapfile
        btrfs property set /mnt/swap/swapfile compression none
        dd if=/dev/zero of=/mnt/swap/swapfile bs=1M count="$SWAP_SIZE" status=progress
        chmod 600 /mnt/swap/swapfile
        mkswap /mnt/swap/swapfile
        swapon /mnt/swap/swapfile
    fi
else
    info "Mounting ext4 filesystem..."
    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg}
    
    if [[ -n "$SWAP_SIZE" ]]; then
        info "Creating swap file..."
        dd if=/dev/zero of=/mnt/swapfile bs=1M count="$SWAP_SIZE" status=progress
        chmod 600 /mnt/swapfile
        mkswap /mnt/swapfile
        swapon /mnt/swapfile
    fi
fi

# Mount boot partition for UEFI
if [[ "$BOOT_MODE" == "uefi" ]]; then
    mkdir -p /mnt/boot
    mount "$BOOT_PART" /mnt/boot
fi

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

pacstrap /mnt $BASE_PACKAGES

info "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Copy the installation folder to the new system for the second stage
cp -r "${SCRIPT_DIR}" /mnt/root/arch-install

# Save installation metadata for post.sh
cat > /mnt/root/arch-install/.install-meta << EOF
BOOT_MODE=$BOOT_MODE
BOOTLOADER=$BOOTLOADER
FILESYSTEM=$FILESYSTEM
DISK=$DISK
INSTALL_KZSH=$INSTALL_KZSH
EOF

success "Stage 1 (Prep) complete."
info "Now run: arch-chroot /mnt /root/arch-install/post.sh --hostname $HOSTNAME --user $USERNAME --profile $PROFILE"
