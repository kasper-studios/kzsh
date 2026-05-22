#!/usr/bin/env bash
set -euo pipefail

echo "== Running Desktop KDE Plasma Profile =="

# Install KDE Plasma desktop environment
pacman -S --noconfirm \
    plasma-meta \
    kde-applications-meta \
    sddm \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    wireplumber

# Enable SDDM
systemctl enable sddm

echo "== Desktop KDE Plasma Profile Complete =="
