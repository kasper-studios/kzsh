#!/bin/bash
# Post-install hook for desktop-xfce profile
set -e

echo "Configuring XFCE4 desktop environment..."

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

echo "XFCE4 configured successfully! LightDM display manager enabled."
