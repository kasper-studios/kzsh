#!/usr/bin/env bash
set -euo pipefail

echo "== Running Base Profile =="

# Install common utilities
pacman -S --noconfirm \
    htop \
    tree \
    fastfetch \
    rsync \
    zip \
    unzip \
    wget \
    man-db \
    man-pages \
    texinfo

echo "== Base Profile Complete =="
