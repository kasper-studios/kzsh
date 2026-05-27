#!/bin/bash
# Post-install hook for profile: desktop-niri
# Goal: make a fresh Arch install boot into a working greeter + Niri session reliably.

set -e

echo "Configuring Niri desktop environment..."

# ------------------------------
# Prerequisites
# ------------------------------
if ! command -v pacman >/dev/null 2>&1; then
  echo "ERROR: This hook is for Arch Linux only (pacman not found)."
  exit 1
fi

if [[ "$EUID" -eq 0 ]]; then
  echo "ERROR: Do not run this hook as root. Run as your user (with sudo available)."
  exit 1
fi

# ------------------------------
# Helpers
# ------------------------------
_have_cmd() { command -v "$1" >/dev/null 2>&1; }

_pac_install() {
  # Install packages via pacman with sudo if needed.
  # Usage: _pac_install pkg1 pkg2 ...
  if [[ $# -eq 0 ]]; then
    return 0
  fi

  if [[ "$EUID" -ne 0 ]]; then
    sudo pacman -S --noconfirm --needed "$@"
  else
    pacman -S --noconfirm --needed "$@"
  fi
}

_warn() { echo "WARN: $*"; }


# ------------------------------
# AUR helper + AUR deps
# ------------------------------
_ensure_aur_helper() {
  if _have_cmd yay || _have_cmd paru; then
    return 0
  fi

  echo "Installing yay (AUR helper)..."
  _pac_install base-devel git || return 1

  local tmp
  tmp=$(mktemp -d)

  if ! git clone --depth=1 https://aur.archlinux.org/yay.git "$tmp/yay"; then
    rm -rf "$tmp"
    return 1
  fi

  (
    cd "$tmp/yay"
    makepkg -si --noconfirm
  ) || {
    rm -rf "$tmp"
    return 1
  }

  rm -rf "$tmp"

  if ! _have_cmd yay; then
    return 1
  fi

  echo "OK: yay installed"
  return 0
}

_install_aur_packages() {
  local helper=""
  if _have_cmd yay; then helper="yay"; fi
  if _have_cmd paru; then helper="paru"; fi

  if [[ -z "$helper" ]]; then
    _warn "No AUR helper available; skipping AUR packages (tofi/quickshell-git)."
    return 0
  fi

  local aur_pkgs=(tofi quickshell-git)
  echo "Installing AUR packages: ${aur_pkgs[*]}"
  if ! "$helper" -S --noconfirm --needed "${aur_pkgs[@]}"; then
    _warn "Some AUR packages failed to install; continuing."
  fi
}

if ! _ensure_aur_helper; then
  _warn "Failed to install AUR helper; skipping AUR packages."
else
  _install_aur_packages
fi

# Do GPU preflight after having basic tooling (and before greeter enable is fine)
_install_gpu_drivers_safe

# ------------------------------
# Wayland environment variables
# ------------------------------
echo "Setting up Wayland environment variables..."
mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/wayland.conf" << 'EOF'
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
EOF

echo "OK: ~/.config/environment.d/wayland.conf"

# ------------------------------
# Register Niri session for SDDM
# ------------------------------
echo "Registering Niri Wayland session for SDDM..."
sudo mkdir -p /usr/share/wayland-sessions
sudo tee /usr/share/wayland-sessions/niri.desktop >/dev/null << 'EOF'
[Desktop Entry]
Name=Niri
Comment=Niri scrolling Wayland compositor
Exec=niri-session
Type=Application
DesktopNames=niri
EOF

echo "OK: /usr/share/wayland-sessions/niri.desktop"

# ------------------------------
# SDDM configuration (greeter reliability first)
# ------------------------------
echo "Configuring SDDM (safe defaults)..."

sudo mkdir -p /etc/sddm.conf.d

SDDM_MODE="x11"
SDDM_COMPOSITOR=""

# Wayland greeter requires a compositor.
# We only enable Wayland greeter if a known compositor exists.
if _have_cmd kwin_wayland; then
  SDDM_MODE="wayland"
  SDDM_COMPOSITOR="kwin_wayland --no-lockscreen --no-global-shortcuts --locale1"
fi

if [[ "$SDDM_MODE" == "wayland" ]]; then
  echo "OK: Wayland greeter enabled (compositor: $SDDM_COMPOSITOR)"
  sudo tee /etc/sddm.conf.d/10-kzsh.conf >/dev/null << EOF
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
CompositorCommand=$SDDM_COMPOSITOR

[Autologin]
Relogin=false
EOF
else
  _warn "No Wayland compositor detected for SDDM greeter. Using X11 greeter (recommended)."
  sudo tee /etc/sddm.conf.d/10-kzsh.conf >/dev/null << 'EOF'
[General]
DisplayServer=x11

[Autologin]
Relogin=false
EOF
fi

echo "OK: /etc/sddm.conf.d/10-kzsh.conf (mode: $SDDM_MODE)"

echo "Enabling SDDM service..."
if [[ -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ]]; then
  sudo rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
  sudo rmdir /etc/systemd/system/getty@tty1.service.d 2>/dev/null || true
  echo "OK: removed old getty@tty1 autologin override"
fi

sudo systemctl daemon-reload
sudo systemctl enable --now sddm.service

echo "OK: sddm.service enabled and started"

# ------------------------------
# TTY1 fallback autostart (no exec)
# ------------------------------
NIRI_AUTOSTART_MARKER="# kzsh: niri-session autostart"
ZSHRC="$HOME/.zshrc"

if ! grep -qF "$NIRI_AUTOSTART_MARKER" "$ZSHRC" 2>/dev/null; then
  cat >> "$ZSHRC" << 'AUTOSTART'

# kzsh: niri-session autostart (TTY1 fallback; SDDM is primary)
if [[ -z "$WAYLAND_DISPLAY" && -z "$DISPLAY" && "$XDG_VTNR" == "1" ]]; then
  niri-session
fi
AUTOSTART
  echo "OK: TTY1 fallback autostart added to $ZSHRC"
fi

# ------------------------------
# Minimal Niri config (only if missing)
# ------------------------------
if [[ ! -f "$HOME/.config/niri/config.kdl" ]]; then
  echo "Creating Niri config at ~/.config/niri/config.kdl ..."
  mkdir -p "$HOME/.config/niri"
  cat > "$HOME/.config/niri/config.kdl" << 'EOF'
// Minimal Niri config generated by kzsh

input {
    keyboard {
        xkb {
            layout "us,ua"
            options "grp:alt_shift_toggle"
        }
    }
}

layout {
    gaps 10
}

binds {
    // Launch
    Mod+Return { spawn "kitty"; }
    Mod+T      { spawn "kitty"; }
    Mod+D      { spawn "tofi-run"; }
    Mod+E      { spawn "thunar"; }
    Mod+B      { spawn "firefox"; }

    // Window
    Mod+Q { close-window; }
    Mod+F { maximize-column; }
    Mod+Shift+F { fullscreen-window; }

    // Focus
    Mod+Left  { focus-column-left; }
    Mod+Right { focus-column-right; }
    Mod+Up    { focus-window-up; }
    Mod+Down  { focus-window-down; }

    // Workspaces
    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }

    Mod+Shift+1 { move-column-to-workspace 1; }
    Mod+Shift+2 { move-column-to-workspace 2; }
    Mod+Shift+3 { move-column-to-workspace 3; }
    Mod+Shift+4 { move-column-to-workspace 4; }

    // Screenshots
    Print { screenshot; }

    // Exit
    Mod+Shift+E { quit; }
}
EOF
  mkdir -p "$HOME/Pictures/Screenshots" || true
  echo "OK: Niri config created"
else
  echo "Niri config already exists, skipping"
fi

# ------------------------------
# DankMaterialShell (optional)
# ------------------------------
if [[ ! -d "$HOME/.config/quickshell" ]] || [[ -z "$(ls -A "$HOME/.config/quickshell" 2>/dev/null)" ]]; then
  echo "Installing DankMaterialShell (optional)..."
  if curl -fsSL https://install.danklinux.com | sh; then
    echo "OK: DankMaterialShell installed"
  else
    _warn "DankMaterialShell install failed. You can install manually: curl -fsSL https://install.danklinux.com | sh"
  fi
else
  echo "DankMaterialShell already present (~/.config/quickshell), skipping"
fi

# ------------------------------
# Groups
# ------------------------------
echo "Adding user to video and input groups..."
if ! groups | grep -q "\bvideo\b"; then
  sudo usermod -aG video "$USER" || _warn "Failed to add user to video group"
fi
if ! groups | grep -q "\binput\b"; then
  sudo usermod -aG input "$USER" || _warn "Failed to add user to input group"
fi

# ------------------------------
# XDG user dirs
# ------------------------------
if _have_cmd xdg-user-dirs-update; then
  xdg-user-dirs-update || true
  echo "OK: XDG user dirs updated"
fi

 # ------------------------------
 # Summary
 # ------------------------------
echo ""
echo "OK: Niri desktop configured."
echo ""
echo "  Display manager : SDDM (enabled and started)"
echo "  Session file    : /usr/share/wayland-sessions/niri.desktop"
echo "  SDDM config     : /etc/sddm.conf.d/10-kzsh.conf"
echo "  Niri config     : ~/.config/niri/config.kdl"
echo "  TTY1 fallback   : ~/.zshrc (without exec)"
echo ""
echo "Reboot to start SDDM -> select 'Niri' session."
