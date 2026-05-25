#!/bin/bash
# Post-install hook for desktop-niri profile

set -e  # Exit on error

echo "Configuring Niri desktop environment..."

# ─── Check prerequisites ────────────────────────────────────────────────────────
if ! command -v pacman &>/dev/null; then
  echo "✗ This hook is for Arch Linux only"
  exit 1
fi

if [[ "$EUID" -eq 0 ]]; then
  echo "✗ Do not run this hook as root"
  exit 1
fi

# ─── Ensure yay is available (needed for AUR packages) ────────────────────────
_ensure_yay() {
  if command -v yay &>/dev/null || command -v paru &>/dev/null; then
    return 0
  fi

  echo "Installing yay (AUR helper)..."
  
  # Check if base-devel is installed
  if ! pacman -Qq base-devel &>/dev/null; then
    sudo pacman -S --noconfirm --needed base-devel git || {
      echo "✗ Failed to install base-devel"
      return 1
    }
  fi

  local tmp
  tmp=$(mktemp -d)
  
  if ! git clone --depth=1 https://aur.archlinux.org/yay.git "$tmp/yay"; then
    echo "✗ Failed to clone yay repository"
    rm -rf "$tmp"
    return 1
  fi
  
  (cd "$tmp/yay" && makepkg -si --noconfirm) || {
    echo "✗ Failed to build yay"
    rm -rf "$tmp"
    return 1
  }
  
  rm -rf "$tmp"

  if ! command -v yay &>/dev/null; then
    echo "✗ yay install failed"
    return 1
  fi
  
  echo "✓ yay installed"
  return 0
}

# ─── Install AUR packages ───────────────────────────────────────────────────────
_install_aur_deps() {
  local aur_helper
  if command -v yay &>/dev/null; then
    aur_helper="yay"
  elif command -v paru &>/dev/null; then
    aur_helper="paru"
  else
    echo "✗ No AUR helper found"
    return 1
  fi

  local aur_pkgs=(tofi quickshell-git)
  echo "Installing AUR packages: ${aur_pkgs[*]}..."
  
  if ! "$aur_helper" -S --noconfirm --needed "${aur_pkgs[@]}"; then
    echo "⚠ Some AUR packages failed to install, continuing..."
  fi
}

if ! _ensure_yay; then
  echo "⚠ Failed to install yay, skipping AUR packages"
else
  _install_aur_deps
fi

# ─── Wayland environment variables (environment.d) ────────────────────────────
# These are picked up by systemd --user and imported into the session
# properly, avoiding the "import-environment without variable names" warning.
echo "Setting up Wayland environment variables..."
mkdir -p ~/.config/environment.d
cat > ~/.config/environment.d/wayland.conf << 'EOF'
XDG_SESSION_TYPE=wayland
XDG_SESSION_DESKTOP=niri
XDG_CURRENT_DESKTOP=niri
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
ELECTRON_OZONE_PLATFORM_HINT=auto
GDK_BACKEND=wayland,x11
SDL_VIDEODRIVER=wayland
CLUTTER_BACKEND=wayland
NITROSOCK_WAYLAND=1
EOF
echo "✓ Wayland env vars written to ~/.config/environment.d/wayland.conf"

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
  echo "✓ Niri config created"
else
  echo "⚠ Niri config already exists, skipping"
fi

# ─── DankMaterialShell ────────────────────────────────────────────────────────
if ! command -v dank-shell &>/dev/null && [[ ! -f "$HOME/.config/quickshell/shell.qml" ]]; then
  echo "Installing DankMaterialShell..."
  if curl -fsSL https://install.danklinux.com | sh; then
    echo "✓ DankMaterialShell installed"
  else
    echo "⚠ DankMaterialShell installation failed, skipping"
  fi
else
  echo "⚠ DankMaterialShell already installed, skipping"
fi

# ─── Groups ───────────────────────────────────────────────────────────────────
echo "Adding user to video and input groups..."
groups | grep -q video || sudo usermod -aG video "$USER" || echo "⚠ Failed to add to video group"
groups | grep -q input || sudo usermod -aG input "$USER" || echo "⚠ Failed to add to input group"

echo ""
echo "✓ Niri desktop configured!"
echo "  Reboot → TTY1 autologin → niri-session starts automatically"
echo ""
echo "Keybinds:"
echo "  Super+T       - kitty"
echo "  Super+D       - tofi launcher"
echo "  Super+Q       - close window"
echo "  Super+Shift+E - exit niri"
