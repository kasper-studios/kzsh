#!/bin/bash
# Post-install hook for desktop-niri profile

echo "Configuring Niri desktop environment..."

# Disable display managers (we'll use KZSH session manager)
for dm in sddm gdm lightdm; do
    if systemctl is-enabled "$dm" &>/dev/null; then
        echo "Disabling $dm (using KZSH session manager instead)..."
        sudo systemctl disable "$dm" 2>/dev/null || true
        sudo systemctl stop "$dm" 2>/dev/null || true
    fi
done

# Create default Niri config if it doesn't exist
if [[ ! -f ~/.config/niri/config.kdl ]]; then
    echo "Creating default Niri config..."
    mkdir -p ~/.config/niri
    cat > ~/.config/niri/config.kdl << 'EOF'
input {
    keyboard {
        xkb {
            layout "us"
        }
    }
    
    touchpad {
        tap
        natural-scroll
    }
}

output "eDP-1" {
    scale 1.0
}

layout {
    gaps 8
    center-focused-column "never"
}

binds {
    Mod+T { spawn "alacritty"; }
    Mod+D { spawn "fuzzel"; }
    Mod+Q { close-window; }
    Mod+Shift+E { quit; }
    
    Mod+Left  { focus-column-left; }
    Mod+Right { focus-column-right; }
    Mod+Up    { focus-window-up; }
    Mod+Down  { focus-window-down; }
    
    Mod+Ctrl+Left  { move-column-left; }
    Mod+Ctrl+Right { move-column-right; }
    
    Mod+Page_Down { focus-workspace-down; }
    Mod+Page_Up   { focus-workspace-up; }
    
    Mod+Shift+Page_Down { move-column-to-workspace-down; }
    Mod+Shift+Page_Up   { move-column-to-workspace-up; }
    
    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
    
    Mod+Shift+1 { move-column-to-workspace 1; }
    Mod+Shift+2 { move-column-to-workspace 2; }
    Mod+Shift+3 { move-column-to-workspace 3; }
    Mod+Shift+4 { move-column-to-workspace 4; }
    
    Mod+F { maximize-column; }
    Mod+Shift+F { fullscreen-window; }
    
    Print { screenshot; }
    Mod+Print { screenshot-window; }
}

prefer-no-csd

screenshot-path "~/Pictures/Screenshots/screenshot-%Y-%m-%d-%H-%M-%S.png"
EOF
    
    # Create screenshots directory
    mkdir -p ~/Pictures/Screenshots
fi

# Configure SDDM for Wayland
if [[ ! -f /etc/sddm.conf.d/wayland.conf ]]; then
    echo "Configuring SDDM for Wayland..."
    sudo mkdir -p /etc/sddm.conf.d
    sudo tee /etc/sddm.conf.d/wayland.conf > /dev/null << 'EOF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
SessionDir=/usr/share/wayland-sessions
EOF
fi

# Enable SDDM if not already enabled
if ! systemctl is-enabled sddm &>/dev/null; then
    echo "Enabling SDDM..."
    sudo systemctl enable sddm
fi

    mkdir -p ~/Pictures/Screenshots
fi

# Add user to video and input groups if not already
if ! groups | grep -q video; then
    echo "Adding user to video group..."
    sudo usermod -aG video "$USER"
fi

if ! groups | grep -q input; then
    echo "Adding user to input group..."
    sudo usermod -aG input "$USER"
fi

echo "✓ Niri desktop environment configured successfully!"
echo ""
echo "KZSH Session Manager is now enabled!"
echo ""
echo "Next steps:"
echo "  1. Reboot your system: sudo reboot"
echo "  2. After login, KZSH will automatically show session selection"
echo "  3. Select Niri to start the compositor"
echo ""
echo "Keybinds:"
echo "  Super+T - Open terminal (Alacritty)"
echo "  Super+D - App launcher (Fuzzel)"
echo "  Super+Q - Close window"
echo "  Super+Shift+E - Exit Niri"
echo ""
echo "To disable auto-start: kcfg set auto_start_session no"
echo ""
echo "Note: You may need to log out and log back in for group changes to take effect."
