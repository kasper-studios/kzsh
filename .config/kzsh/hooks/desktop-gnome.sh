#!/bin/bash
# Post-install hook for desktop-gnome profile

echo "Configuring GNOME desktop environment..."

# Enable GDM if not already enabled
if ! systemctl is-enabled gdm &>/dev/null; then
    echo "Enabling GDM..."
    sudo systemctl enable gdm
fi

# Add user to video group if not already
if ! groups | grep -q video; then
    echo "Adding user to video group..."
    sudo usermod -aG video "$USER"
fi

echo "✓ GNOME desktop environment configured successfully!"
echo ""
echo "Next steps:"
echo "  1. Reboot your system: sudo reboot"
echo "  2. GDM will start automatically and show the login screen"
echo ""
echo "Note: You may need to log out and log back in for group changes to take effect."
