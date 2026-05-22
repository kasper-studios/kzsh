#!/usr/bin/env bash
set -euo pipefail

echo "== Running Base Profile =="

# Install common utilities
pacman -S --noconfirm \
    htop \
    btop \
    tree \
    fastfetch \
    rsync \
    zip \
    unzip \
    wget \
    curl \
    man-db \
    man-pages \
    texinfo \
    bash-completion \
    less \
    which

echo "== Base Profile Complete =="
