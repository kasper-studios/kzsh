#!/usr/bin/env bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
info() { printf "${BLUE}[INFO]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; exit 1; }
success() { printf "${GREEN}[OK]${NC} %s\n" "$1"; }

# Checks
check_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        error "Not booted in UEFI mode. This installer only supports UEFI."
    fi
}

check_internet() {
    info "Checking internet connection..."
    if ! ping -c 1 archlinux.org &>/dev/null; then
        error "No internet connection detected."
    fi
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

# Helper to find EFI and ROOT partitions based on disk name
get_partitions() {
    local disk="$1"
    if [[ "$disk" == *"nvme"* ]] || [[ "$disk" == *"mmcblk"* ]]; then
        EFI_PART="${disk}p1"
        ROOT_PART="${disk}p2"
    else
        EFI_PART="${disk}1"
        ROOT_PART="${disk}2"
    fi
}
