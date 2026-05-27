#!/bin/bash
# Post-install hook for desktop-gnome profile

set -e

echo "Configuring GNOME desktop environment..."

# Enable GDM if not already enabled
if ! systemctl is-enabled gdm &>/dev/null; then
  echo "Enabling GDM..."
  sudo systemctl enable gdm
fi

# Add user to video group if not already
for group in video input; do
  if ! groups | grep -qw "$group"; then
    echo "Adding user to $group group..."
    sudo usermod -aG "$group" "$USER" || warn "Failed to add user to $group group"
  fi
done

echo "GNOME desktop environment configured successfully!"
echo ""
echo "Next steps:"
echo "  1. Reboot your system: sudo reboot"
echo "  2. GDM will start automatically and show the login screen"
echo ""
echo "Note: You may need to log out and log back in for group changes to take effect."
