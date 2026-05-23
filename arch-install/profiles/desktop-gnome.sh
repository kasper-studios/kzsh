#!/bin/bash
set -euo pipefail

echo "== Running Desktop GNOME Profile =="

# Install GNOME desktop environment
pacman -S --noconfirm \
    gnome \
    gnome-extra \
    gdm \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    wireplumber \
    firefox \
    xdg-user-dirs

# Enable GDM
systemctl enable gdm

# Create user directories
xdg-user-dirs-update

echo "== Desktop GNOME Profile Complete =="
