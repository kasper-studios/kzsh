#!/usr/bin/env bash
# Quick test script to validate boot mode detection

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/lib/common.sh"

echo "=== Boot Mode Detection Test ==="
echo

# Test 1: Detect current boot mode
BOOT_MODE=$(detect_boot_mode)
echo "✓ Detected boot mode: $BOOT_MODE"

# Test 2: Check function
check_boot_mode

# Test 3: Partition naming
echo
echo "=== Partition Naming Test ==="
for disk in "/dev/sda" "/dev/nvme0n1" "/dev/mmcblk0"; do
    echo
    echo "Testing disk: $disk"
    
    # UEFI mode
    get_partitions "$disk" "uefi"
    echo "  UEFI mode:"
    echo "    Boot: $BOOT_PART"
    echo "    Root: $ROOT_PART"
    
    # BIOS mode
    get_partitions "$disk" "bios"
    echo "  BIOS mode:"
    echo "    Root: $ROOT_PART"
done

echo
echo "=== Validation Complete ==="
