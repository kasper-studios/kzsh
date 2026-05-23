#!/bin/bash
set -uo pipefail

# Enable debug mode if DEBUG=1
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x
fi

# KASPERENOK ARCH INSTALLER BOOTSTRAP
# This script clones the full repository and starts the installation.

REPO_URL="https://github.com/kasper-studios/kzsh.git"
echo "== Arch Installer Bootstrap =="

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
