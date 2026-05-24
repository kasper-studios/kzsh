#!/bin/bash
# Post-install hook for desktop-niri profile

echo "Configuring Niri desktop environment..."

# ─── Ensure yay is available (needed for AUR packages) ────────────────────────
_ensure_yay() {
  if command -v yay &>/dev/null; then
    return 0
  fi
  if command -v paru &>/dev/null; then
    return 0
  fi

  echo "Installing yay (AUR helper)..."

  if ! pacman -Qq base-devel &>/dev/null; then
    sudo pacman -S --noconfirm --needed base-devel
  fi
  if ! pacman -Qq git &>/dev/null; then
    sudo pacman -S --noconfirm --needed git
  fi

  local tmp
  tmp=$(mktemp -d)
  git clone --depth=1 https://aur.archlinux.org/yay.git "$tmp/yay"
  (cd "$tmp/yay" && makepkg -si --noconfirm)
  rm -rf "$tmp"

  if command -v yay &>/dev/null; then
    echo "✓ yay installed"
  else
    echo "✗ yay install failed, aborting"
    exit 1
  fi
}

# ─── Install AUR packages that pacman can't handle ────────────────────────────
_install_aur_deps() {
  local aur_helper
  if command -v yay &>/dev/null; then
    aur_helper="yay"
  elif command -v paru &>/dev/null; then
    aur_helper="paru"
  else
    echo "✗ No AUR helper found"
    exit 1
  fi

  local aur_pkgs=(tofi quickshell-git)
  echo "Installing AUR packages: ${aur_pkgs[*]}..."
  "$aur_helper" -S --noconfirm --needed "${aur_pkgs[@]}"
}

# Run AUR setup
_ensure_yay
_install_aur_deps

# ─── Default Niri config ──────────────────────────────────────────────────────
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

# ─── Disable KZSH TTY session manager (using SDDM instead) ───────────────────
sed -i 's/auto_start_session: yes/auto_start_session: no/' \
  "${KZSH_DIR:-$HOME/.config/kzsh}/config.yaml" 2>/dev/null || true

# ─── DankMaterialShell ────────────────────────────────────────────────────────
if ! command -v dank-shell &>/dev/null && [[ ! -f "$HOME/.config/quickshell/shell.qml" ]]; then
  echo "Installing DankMaterialShell..."
  curl -fsSL https://install.danklinux.com | sh
  echo "✓ DankMaterialShell installed"
else
  echo "⚠ DankMaterialShell already installed, skipping"
fi

# ─── SDDM Wayland config ─────────────────────────────────────────────────────
# niri.desktop is shipped by the niri package — no need to create it manually
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

# ─── Enable SDDM ─────────────────────────────────────────────────────────────
if ! systemctl is-enabled sddm &>/dev/null; then
  echo "Enabling SDDM..."
  sudo systemctl enable sddm
fi

# ─── Groups ───────────────────────────────────────────────────────────────────
groups | grep -q video || sudo usermod -aG video "$USER"
groups | grep -q input || sudo usermod -aG input "$USER"

echo ""
echo "✓ Niri desktop configured!"
echo ""
echo "Next steps:"
echo "  1. Reboot: sudo reboot"
echo "  2. SDDM will greet you, select Niri session"
echo ""
echo "Keybinds:"
echo "  Super+T       - kitty"
echo "  Super+D       - tofi launcher"
echo "  Super+Q       - close window"
echo "  Super+Shift+E - exit niri"
