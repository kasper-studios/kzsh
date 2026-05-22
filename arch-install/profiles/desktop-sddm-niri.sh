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
    qt5-wayland \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    wireplumber \
    grim \
    slurp \
    wl-clipboard \
    firefox \
    thunar \
    file-roller \
    xdg-user-dirs

# Enable SDDM
systemctl enable sddm

# Create user directories
xdg-user-dirs-update

# Configure SDDM for Wayland session
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/wayland.conf << 'EOF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
CompositorCommand=niri-session
EOF

echo "== Desktop SDDM Niri Profile Complete =="
