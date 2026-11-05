#!/bin/bash
# Post-install hook for desktop-sway profile
set -e

echo "Configuring Sway Wayland compositor..."

if ! systemctl is-enabled sddm &>/dev/null; then
  echo "Enabling SDDM..."
  sudo systemctl enable sddm
fi

for group in video input; do
  if ! groups | grep -qw "$group"; then
    echo "Adding user to $group group..."
    sudo usermod -aG "$group" "$USER" || echo "WARN: Failed to add user to $group group"
  fi
done

mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/sway.conf" << 'EOF'
XDG_SESSION_TYPE=wayland
XDG_SESSION_DESKTOP=sway
XDG_CURRENT_DESKTOP=sway
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
GDK_BACKEND=wayland
EOF

echo "Sway configured successfully!"
