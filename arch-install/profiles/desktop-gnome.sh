#!/usr/bin/env bash
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
    wireplumber

# Enable GDM
systemctl enable gdm

echo "== Desktop GNOME Profile Complete =="
