#!/bin/bash
set -uo pipefail

# Enable debug mode if DEBUG=1
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x
fi

# KASPERENOK ARCH INSTALLER BOOTSTRAP
# This script clones the full repository and starts the installation.

REPO_URL="https://github.com/kasper-studios/kzsh.git"
INSTALL_ROOT="/install-root"

echo "== Arch Installer Bootstrap =="

# Check if installation already exists
if [[ -d "$INSTALL_ROOT/root/arch-install" ]] && [[ -f "$INSTALL_ROOT/etc/fstab" ]]; then
    echo ""
    echo ">> Existing installation detected at $INSTALL_ROOT"
    echo ""
    echo "Options:"
    echo "  1) Update installer scripts and continue with post.sh"
    echo "  2) Start fresh installation (will erase everything)"
    echo "  3) Exit"
    echo ""
    
    # Use /dev/tty for input when stdin is redirected
    if [[ -t 0 ]]; then
        read -p "Choose option [1-3]: " choice
    elif [[ -e /dev/tty ]]; then
        read -p "Choose option [1-3]: " choice < /dev/tty
    else
        echo ">> Non-interactive mode detected. Use --force to start fresh installation."
        echo ">> Or run post.sh manually:"
        echo ""
        echo "   arch-chroot $INSTALL_ROOT /root/arch-install/post.sh \\"
        echo "     --hostname YOUR_HOSTNAME \\"
        echo "     --user YOUR_USERNAME \\"
        echo "     --profile YOUR_PROFILE \\"
        echo "     --kzsh yes"
        echo ""
        exit 1
    fi
    
    case $choice in
        1)
            echo ">> Updating installer scripts..."
            # Clone to temp directory
            TMP_REPO=$(mktemp -d)
            if ! command -v git >/dev/null 2>&1; then
                echo ">> Git not found, installing..."
                pacman -Sy --noconfirm git
            fi
            git clone --depth 1 "$REPO_URL" "$TMP_REPO"
            
            # Update scripts in the installed system
            echo ">> Copying updated scripts to $INSTALL_ROOT/root/arch-install..."
            cp -rf "$TMP_REPO/arch-install/"* "$INSTALL_ROOT/root/arch-install/"
            chmod +x "$INSTALL_ROOT/root/arch-install/post.sh"
            chmod +x "$INSTALL_ROOT/root/arch-install/prep.sh"
            chmod +x "$INSTALL_ROOT/root/arch-install/bootstrap.sh"
            
            # Clean up temp repo
            rm -rf "$TMP_REPO"
            
            echo ""
            echo ">> Scripts updated successfully!"
            echo ">> Now run post.sh with your parameters:"
            echo ""
            echo "   arch-chroot $INSTALL_ROOT /root/arch-install/post.sh \\"
            echo "     --hostname YOUR_HOSTNAME \\"
            echo "     --user YOUR_USERNAME \\"
            echo "     --profile YOUR_PROFILE \\"
            echo "     --kzsh yes"
            echo ""
            exit 0
            ;;
        2)
            echo ">> Starting fresh installation..."
            # Continue with normal flow
            ;;
        3)
            echo ">> Exiting..."
            exit 0
            ;;
        *)
            echo ">> Invalid option, exiting..."
            exit 1
            ;;
    esac
fi

# 1. Ensure git is installed
if ! command -v git >/dev/null 2>&1; then
    echo ">> Git not found, installing..."
    pacman -Sy --noconfirm git
fi

# 2. Clone repository to temporary directory
TMP_REPO=$(mktemp -d)
echo ">> Cloning repository (depth=1)..."
git clone --depth 1 "$REPO_URL" "$TMP_REPO"

# 3. Execute prep.sh from the repository
echo ">> Starting Stage 1 (prep.sh)..."
echo ">> Arguments: $@"
exec bash "$TMP_REPO/arch-install/prep.sh" "$@"
