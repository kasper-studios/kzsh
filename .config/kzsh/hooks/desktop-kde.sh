#!/bin/bash
# Post-install hook for desktop-kde profile

echo "Configuring KDE Plasma desktop environment..."

# Enable SDDM if not already enabled
if ! systemctl is-enabled sddm &>/dev/null; then
    echo "Enabling SDDM..."
    sudo systemctl enable sddm
fi

# Add user to video group if not already
if ! groups | grep -q video; then
    echo "Adding user to video group..."
    sudo usermod -aG video "$USER"
fi

echo "вњ“ KDE Plasma desktop environment configured successfully!"
echo ""
echo "Next steps:"
echo "  1. Reboot your system: sudo reboot"
echo "  2. SDDM will start automatically and show the login screen"
echo "  3. Select 'Plasma' session if not selected by default"
echo ""
echo "Note: You may need to log out and log back in for group changes to take effect."
