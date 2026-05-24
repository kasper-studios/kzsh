#!/bin/bash
# Post-install hook for desktop-niri profile

echo "Configuring Niri desktop environment..."

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
    Mod+T { spawn "kitty"; }
    Mod+D { spawn "tofi-run"; }
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
    mkdir -p ~/Pictures/Screenshots
fi

# Install DankMaterialShell
if [[ ! -d "$HOME/.local/share/danklinux" ]]; then
    echo "Installing DankMaterialShell..."
    curl -fsSL https://danklinux.com/install.sh | bash
    echo "✓ DankMaterialShell installed"
else
    echo "⚠ DankMaterialShell already installed, skipping"
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

# Enable SDDM
if ! systemctl is-enabled sddm &>/dev/null; then
    echo "Enabling SDDM..."
    sudo systemctl enable sddm
fi

# Add user to video and input groups
if ! groups | grep -q video; then
    sudo usermod -aG video "$USER"
fi
if ! groups | grep -q input; then
    sudo usermod -aG input "$USER"
fi

echo "✓ Niri desktop configured!"
echo ""
echo "Next steps:"
echo "  1. Reboot: sudo reboot"
echo "  2. SDDM will greet you, select Niri session"
echo ""
echo "Keybinds:"
echo "  Super+T  - kitty"
echo "  Super+D  - tofi launcher"
echo "  Super+Q  - close window"
echo "  Super+Shift+E - exit niri"
