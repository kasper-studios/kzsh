#!/bin/bash
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
    wireplumber \
    firefox \
    xdg-user-dirs

# Enable SDDM
systemctl enable sddm

# Create user directories
xdg-user-dirs-update

echo "== Desktop KDE Plasma Profile Complete =="
