#!/usr/bin/env bash
set -euo pipefail

echo "== Running Desktop SDDM Niri Profile =="

# Install display server, compositor and display manager
pacman -S --noconfirm \
    niri \
    sddm \
    waybar \
    alacritty \
    mako \
    fuzzel \
    swaybg \
    xorg-xwayland \
    qt6-wayland \
    qt5-wayland

# Enable SDDM
systemctl enable sddm

# Basic configuration for SDDM to use Wayland (optional, usually default now)
# mkdir -p /etc/sddm.conf.d
# cat > /etc/sddm.conf.d/wayland.conf << EOF
# [General]
# DisplayServer=wayland
# EOF

echo "== Desktop SDDM Niri Profile Complete =="
