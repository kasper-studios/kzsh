#!/bin/bash
# Post-install hook for desktop-hyprland profile
set -e

echo "Configuring Hyprland Wayland compositor..."

# Enable SDDM
if ! systemctl is-enabled sddm &>/dev/null; then
  echo "Enabling SDDM..."
  sudo systemctl enable sddm
fi

# Add user to video/input
for group in video input; do
  if ! groups | grep -qw "$group"; then
    echo "Adding user to $group group..."
    sudo usermod -aG "$group" "$USER" || echo "WARN: Failed to add user to $group group"
  fi
done

# Wayland env setup
mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/hyprland.conf" << 'EOF'
XDG_SESSION_TYPE=wayland
XDG_SESSION_DESKTOP=Hyprland
XDG_CURRENT_DESKTOP=Hyprland
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland;xcb
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
ELECTRON_OZONE_PLATFORM_HINT=auto
GDK_BACKEND=wayland,x11
SDL_VIDEODRIVER=wayland
CLUTTER_BACKEND=wayland
EOF

echo "Hyprland configured successfully!"
echo "Reboot and select 'Hyprland' session in SDDM."
