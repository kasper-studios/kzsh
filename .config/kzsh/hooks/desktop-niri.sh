#!/bin/bash
# Post-install hook for desktop-niri profile

echo "Configuring Niri desktop environment..."

# ─── Ensure yay is available (needed for AUR packages) ────────────────────────
_ensure_yay() {
  if command -v yay &>/dev/null || command -v paru &>/dev/null; then
    return 0
  fi

  echo "Installing yay (AUR helper)..."
  sudo pacman -S --noconfirm --needed base-devel git

  local tmp
  tmp=$(mktemp -d)
  git clone --depth=1 https://aur.archlinux.org/yay.git "$tmp/yay"
  (cd "$tmp/yay" && makepkg -si --noconfirm)
  rm -rf "$tmp"

  command -v yay &>/dev/null || { echo "✗ yay install failed"; exit 1; }
  echo "✓ yay installed"
}

# ─── Install AUR packages ───────────────────────────────────────────────────────
_install_aur_deps() {
  local aur_helper
  command -v yay &>/dev/null && aur_helper="yay"
  command -v paru &>/dev/null && aur_helper="paru"
  [[ -z "$aur_helper" ]] && { echo "✗ No AUR helper found"; exit 1; }

  local aur_pkgs=(tofi quickshell-git)
  echo "Installing AUR packages: ${aur_pkgs[*]}..."
  "$aur_helper" -S --noconfirm --needed "${aur_pkgs[@]}"
}

_ensure_yay
_install_aur_deps

# ─── TTY1 autologin ────────────────────────────────────────────────────────────────
echo "Setting up TTY1 autologin for $USER..."
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf > /dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
Type=simple
EOF
sudo systemctl daemon-reload
sudo systemctl enable getty@tty1.service
echo "✓ TTY1 autologin configured for $USER"

# ─── niri-session autostart from shell profile ────────────────────────────────────
NIRI_AUTOSTART_MARKER='# kzsh: niri-session autostart'

# Pick the right login profile file
if [[ -f "$HOME/.zprofile" ]]; then
  PROFILE="$HOME/.zprofile"
elif [[ -f "$HOME/.bash_profile" ]]; then
  PROFILE="$HOME/.bash_profile"
else
  PROFILE="$HOME/.bash_profile"
  touch "$PROFILE"
fi

if ! grep -qF "$NIRI_AUTOSTART_MARKER" "$PROFILE"; then
  cat >> "$PROFILE" << 'AUTOSTART'

# kzsh: niri-session autostart
if [ -z "${WAYLAND_DISPLAY}" ] && [ "${XDG_VTNR}" = "1" ]; then
  exec niri-session
fi
AUTOSTART
  echo "✓ niri-session autostart added to $PROFILE"
else
  echo "⚠ niri-session autostart already in $PROFILE, skipping"
fi

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

# ─── DankMaterialShell ────────────────────────────────────────────────────────
if ! command -v dank-shell &>/dev/null && [[ ! -f "$HOME/.config/quickshell/shell.qml" ]]; then
  echo "Installing DankMaterialShell..."
  curl -fsSL https://install.danklinux.com | sh
  echo "✓ DankMaterialShell installed"
else
  echo "⚠ DankMaterialShell already installed, skipping"
fi

# ─── Groups ───────────────────────────────────────────────────────────────────
groups | grep -q video || sudo usermod -aG video "$USER"
groups | grep -q input || sudo usermod -aG input "$USER"

echo ""
echo "✓ Niri desktop configured!"
echo "  Reboot → TTY1 autologin → niri-session starts automatically"
echo ""
echo "Keybinds:"
echo "  Super+T       - kitty"
echo "  Super+D       - tofi launcher"
echo "  Super+Q       - close window"
echo "  Super+Shift+E - exit niri"
