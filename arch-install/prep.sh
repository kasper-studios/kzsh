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

# Default values
DISK=""
HOSTNAME="ponosik"
USERNAME="kasperenok"
PROFILE="desktop-sddm-niri"
SWAP_SIZE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --disk) DISK="$2"; shift 2 ;;
        --hostname) HOSTNAME="$2"; shift 2 ;;
        --user) USERNAME="$2"; shift 2 ;;
        --profile) PROFILE="$2"; shift 2 ;;
        --swap) SWAP_SIZE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

check_uefi
check_internet

# Interactive mode if disk not provided
if [[ -z "$DISK" ]]; then
    info "Available disks:"
    lsblk -d -o NAME,SIZE,MODEL
    echo
    read -rp "Target disk (example: /dev/sda): " DISK
    read -rp "Hostname [$HOSTNAME]: " input_host
    HOSTNAME="${input_host:-$HOSTNAME}"
    read -rp "Username [$USERNAME]: " input_user
    USERNAME="${input_user:-$USERNAME}"
fi

if [[ ! -b "$DISK" ]]; then
    error "Disk not found: $DISK"
fi

confirm_strict "$DISK"

info "Partitioning $DISK..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart ROOT btrfs 513MiB 100%

get_partitions "$DISK"

info "Formatting partitions..."
mkfs.fat -F32 "$EFI_PART"
mkfs.btrfs -f "$ROOT_PART"

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

info "Mounting subvolumes..."
mount -o subvol=@,compress=zstd,noatime "$ROOT_PART" /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg}
mount -o subvol=@home,compress=zstd,noatime "$ROOT_PART" /mnt/home
mount -o subvol=@log,compress=zstd,noatime "$ROOT_PART" /mnt/var/log
mount -o subvol=@pkg,compress=zstd,noatime "$ROOT_PART" /mnt/var/cache/pacman/pkg
mount "$EFI_PART" /mnt/boot

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

info "Installing base system (pacstrap)..."
# Basic packages plus what's needed for the next stage
pacstrap /mnt base linux linux-firmware vim networkmanager git curl zsh btrfs-progs sudo intel-ucode amd-ucode

info "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Copy the installation folder to the new system for the second stage
cp -r "${SCRIPT_DIR}" /mnt/root/arch-install

success "Stage 1 (Prep) complete."
info "Now run: arch-chroot /mnt /root/arch-install/post.sh --hostname $HOSTNAME --user $USERNAME --profile $PROFILE"
