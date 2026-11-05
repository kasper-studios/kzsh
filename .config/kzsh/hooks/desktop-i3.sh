#!/bin/bash
# Post-install hook for desktop-i3 profile
set -e

echo "Configuring i3 window manager..."

if ! systemctl is-enabled lightdm &>/dev/null; then
  echo "Enabling LightDM..."
  sudo systemctl enable lightdm
fi

for group in video input; do
  if ! groups | grep -qw "$group"; then
    echo "Adding user to $group group..."
    sudo usermod -aG "$group" "$USER" || echo "WARN: Failed to add user to $group group"
  fi
done

echo "i3 WM configured successfully! LightDM display manager enabled."
