#!/bin/bash
# Post-install hook for desktop-niri profile

set -e

echo "Configuring Niri desktop environment..."

# ─── Check prerequisites ──────────────────────────────────────────────────────
if ! command -v pacman &>/dev/null; then
  echo "✗ This hook is for Arch Linux only"
  exit 1
fi

if [[ "$EUID" -eq 0 ]]; then
  echo "✗ Do not run this hook as root"
  exit 1
fi

# ─── Ensure yay is available ──────────────────────────────────────────────────
_ensure_yay() {
  if command -v yay &>/dev/null || command -v paru &>/dev/null; then
    return 0
  fi

  echo "Installing yay (AUR helper)..."

  if ! pacman -Qq base-devel &>/dev/null; then
    sudo pacman -S --noconfirm --needed base-devel git || {
      echo "✗ Failed to install base-devel"
      return 1
    }
  fi

  local tmp
  tmp=$(mktemp -d)

  if ! git clone --depth=1 https://aur.archlinux.org/yay.git "$tmp/yay"; then
    echo "✗ Failed to clone yay"
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

# ─── Install AUR packages ─────────────────────────────────────────────────────
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

  # tofi: app launcher | quickshell-git: shell UI framework for DankMaterialShell
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

# ─── Wayland environment variables ───────────────────────────────────────────
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
EOF
echo "✓ Wayland env vars -> ~/.config/environment.d/wayland.conf"

# ─── Wayland session file for SDDM ───────────────────────────────────────────
echo "Registering niri Wayland session for SDDM..."
sudo mkdir -p /usr/share/wayland-sessions
sudo tee /usr/share/wayland-sessions/niri.desktop > /dev/null << 'EOF'
[Desktop Entry]
Name=Niri
Comment=Niri scrolling Wayland compositor
Exec=niri-session
Type=Application
DesktopNames=niri
EOF
echo "✓ /usr/share/wayland-sessions/niri.desktop created"

# ─── SDDM configuration ───────────────────────────────────────────────────────
echo "Configuring SDDM for Wayland..."
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/10-wayland.conf > /dev/null << 'EOF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
CompositorCommand=kwin_wayland --no-lockscreen --no-global-shortcuts --locale1

[Autologin]
Relogin=false
EOF
echo "✓ /etc/sddm.conf.d/10-wayland.conf written"

# ─── Enable SDDM, remove conflicting getty autologin ─────────────────────────
echo "Enabling SDDM service..."
if [[ -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ]]; then
  sudo rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
  sudo rmdir /etc/systemd/system/getty@tty1.service.d 2>/dev/null || true
  echo "✓ Removed old getty@tty1 autologin override (was conflicting with SDDM)"
fi
sudo systemctl daemon-reload
sudo systemctl enable sddm.service
echo "✓ sddm.service enabled"

# ─── TTY1 fallback autostart (NO exec — shell survives niri crash) ────────────
NIRI_AUTOSTART_MARKER='# kzsh: niri-session autostart'
ZSHRC="$HOME/.zshrc"

if ! grep -qF "$NIRI_AUTOSTART_MARKER" "$ZSHRC" 2>/dev/null; then
  cat >> "$ZSHRC" << 'AUTOSTART'

# kzsh: niri-session autostart (TTY1 fallback — SDDM is primary)
if [[ -z "$WAYLAND_DISPLAY" && -z "$DISPLAY" && "$XDG_VTNR" == "1" ]]; then
  niri-session
fi
AUTOSTART
  echo "✓ TTY1 fallback autostart added to $ZSHRC (no exec — shell survives crash)"
else
  if grep -qF 'exec niri-session' "$ZSHRC" 2>/dev/null; then
    sed -i 's/exec niri-session/niri-session/' "$ZSHRC"
    echo "✓ Fixed: removed 'exec' from niri-session autostart in $ZSHRC"
  else
    echo "⚠ niri-session autostart already in $ZSHRC, skipping"
  fi
fi

# ─── Full Niri config ─────────────────────────────────────────────────────────
if [[ ! -f ~/.config/niri/config.kdl ]]; then
  echo "Creating full Niri config..."
  mkdir -p ~/.config/niri
  cat > ~/.config/niri/config.kdl << 'EOF'
// ─── Input ───────────────────────────────────────────────────────────────────
input {
    keyboard {
        xkb {
            layout "us,ua"
            options "grp:alt_shift_toggle"
        }
        repeat-delay 400
        repeat-rate 30
        track-layout "global"
    }

    touchpad {
        tap
        tap-button-map "left-right-middle"
        natural-scroll
        accel-speed 0.2
        accel-profile "adaptive"
        scroll-method "two-finger"
        disabled-on-external-mouse
    }

    mouse {
        accel-speed 0.0
        accel-profile "flat"
    }

    focus-follows-mouse
    workspace-auto-back-and-forth
}

// ─── Output ──────────────────────────────────────────────────────────────────
output "eDP-1" {
    scale 1.0
    transform "normal"
    background-color "#1e1e2e"
}

// ─── Layout ──────────────────────────────────────────────────────────────────
layout {
    gaps 10
    center-focused-column "never"
    always-center-single-column

    preset-column-widths {
        proportion 0.33333
        proportion 0.5
        proportion 0.66667
        proportion 1.0
    }

    default-column-width { proportion 0.5; }

    focus-ring {
        width 2
        active-color "#cba6f7"
        inactive-color "#45475a"
    }

    border {
        off
    }

    shadow {
        on
        softness 20
        spread 5
        offset x=0 y=4
        color "#00000088"
    }

    tab-indicator {
        hide-when-single-tab
        place-within-column
        width 4
        gap 4
        active-color "#cba6f7"
        inactive-color "#45475a"
    }
}

// ─── Animations ──────────────────────────────────────────────────────────────
animations {
    slowdown 1.0

    workspace-switch {
        spring damping-ratio=1.0 stiffness=1000 epsilon=0.0001
    }

    window-open {
        duration-ms 150
        curve "ease-out-expo"
    }

    window-close {
        duration-ms 120
        curve "ease-in"
    }

    horizontal-view-movement {
        spring damping-ratio=1.0 stiffness=800 epsilon=0.0001
    }

    window-movement {
        spring damping-ratio=1.0 stiffness=800 epsilon=0.0001
    }

    config-notification-open-close {
        spring damping-ratio=0.6 stiffness=1000 epsilon=0.001
    }
}

// ─── Window Rules ────────────────────────────────────────────────────────────
window-rule {
    match app-id="firefox"
    open-maximized true
}

window-rule {
    match app-id="thunar"
    default-column-width { proportion 0.4; }
}

window-rule {
    match app-id="kitty"
    default-column-width { proportion 0.5; }
    opacity 0.95
}

window-rule {
    match is-floating=true
    shadow { on; }
}

window-rule {
    match app-id=r#"^(xdg-desktop-portal|polkit-gnome-authentication-agent).*"#
    open-floating true
}

// ─── Binds ───────────────────────────────────────────────────────────────────
binds {
    // ── Launchers ──
    Mod+T { spawn "kitty"; }
    Mod+Return { spawn "kitty"; }
    Mod+D { spawn "tofi-run"; }
    Mod+E { spawn "thunar"; }
    Mod+B { spawn "firefox"; }

    // ── Window management ──
    Mod+Q { close-window; }
    Mod+F { maximize-column; }
    Mod+Shift+F { fullscreen-window; }
    Mod+Space { toggle-window-floating; }
    Mod+C { center-column; }

    // ── Focus (arrows + vim) ──
    Mod+Left  { focus-column-left; }
    Mod+Right { focus-column-right; }
    Mod+Up    { focus-window-up; }
    Mod+Down  { focus-window-down; }
    Mod+H { focus-column-left; }
    Mod+L { focus-column-right; }
    Mod+K { focus-window-up; }
    Mod+J { focus-window-down; }

    // ── Move windows ──
    Mod+Ctrl+Left  { move-column-left; }
    Mod+Ctrl+Right { move-column-right; }
    Mod+Ctrl+Up    { move-window-up; }
    Mod+Ctrl+Down  { move-window-down; }
    Mod+Ctrl+H { move-column-left; }
    Mod+Ctrl+L { move-column-right; }
    Mod+Ctrl+K { move-window-up; }
    Mod+Ctrl+J { move-window-down; }

    // ── Resize ──
    Mod+R { switch-preset-column-width; }
    Mod+Minus       { set-column-width "-5%"; }
    Mod+Equal       { set-column-width "+5%"; }
    Mod+Shift+Minus { set-window-height "-5%"; }
    Mod+Shift+Equal { set-window-height "+5%"; }

    // ── Workspaces ──
    Mod+Page_Down { focus-workspace-down; }
    Mod+Page_Up   { focus-workspace-up; }
    Mod+Tab       { focus-workspace-down; }
    Mod+Shift+Tab { focus-workspace-up; }
    Mod+Shift+Page_Down { move-column-to-workspace-down; }
    Mod+Shift+Page_Up   { move-column-to-workspace-up; }

    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
    Mod+5 { focus-workspace 5; }
    Mod+6 { focus-workspace 6; }
    Mod+7 { focus-workspace 7; }
    Mod+8 { focus-workspace 8; }
    Mod+9 { focus-workspace 9; }

    Mod+Shift+1 { move-column-to-workspace 1; }
    Mod+Shift+2 { move-column-to-workspace 2; }
    Mod+Shift+3 { move-column-to-workspace 3; }
    Mod+Shift+4 { move-column-to-workspace 4; }
    Mod+Shift+5 { move-column-to-workspace 5; }
    Mod+Shift+6 { move-column-to-workspace 6; }
    Mod+Shift+7 { move-column-to-workspace 7; }
    Mod+Shift+8 { move-column-to-workspace 8; }
    Mod+Shift+9 { move-column-to-workspace 9; }

    // ── Screenshots ──
    Print           { screenshot; }
    Mod+Print       { screenshot-window; }
    Mod+Shift+Print { screenshot-screen; }

    // ── Media keys ──
    XF86AudioRaiseVolume  allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"; }
    XF86AudioLowerVolume  allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
    XF86AudioMute         allow-when-locked=true { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
    XF86AudioMicMute      allow-when-locked=true { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle"; }
    XF86MonBrightnessUp   allow-when-locked=true { spawn "brightnessctl" "set" "5%+"; }
    XF86MonBrightnessDown allow-when-locked=true { spawn "brightnessctl" "set" "5%-"; }
    XF86AudioPlay  { spawn "playerctl" "play-pause"; }
    XF86AudioNext  { spawn "playerctl" "next"; }
    XF86AudioPrev  { spawn "playerctl" "previous"; }

    // ── System ──
    Mod+Shift+E { quit; }
    Mod+Shift+R { reload-config; }
    Mod+Shift+P { power-off-monitors; }
    Ctrl+Alt+Delete { spawn "kitty" "-e" "btop"; }
}

// ─── Misc ────────────────────────────────────────────────────────────────────
prefer-no-csd

screenshot-path "~/Pictures/Screenshots/screenshot-%Y-%m-%d-%H-%M-%S.png"

hot-corners {
    off
}
EOF
  mkdir -p ~/Pictures/Screenshots
  echo "✓ Full Niri config created at ~/.config/niri/config.kdl"
else
  echo "⚠ Niri config already exists, skipping (delete to regenerate)"
fi

# ─── DankMaterialShell ────────────────────────────────────────────────────────
if [[ ! -d "$HOME/.config/quickshell" ]] || [[ -z "$(ls -A "$HOME/.config/quickshell" 2>/dev/null)" ]]; then
  echo "Installing DankMaterialShell (quickshell UI for niri)..."
  if curl -fsSL https://install.danklinux.com | sh; then
    echo "✓ DankMaterialShell installed"
  else
    echo "⚠ DankMaterialShell installation failed — install manually:"
    echo "   curl -fsSL https://install.danklinux.com | sh"
  fi
else
  echo "⚠ DankMaterialShell already installed (~/.config/quickshell exists), skipping"
fi

# ─── Groups ───────────────────────────────────────────────────────────────────
echo "Adding user to video and input groups..."
groups | grep -q video || sudo usermod -aG video "$USER" || echo "⚠ Failed to add to video group"
groups | grep -q input || sudo usermod -aG input "$USER" || echo "⚠ Failed to add to input group"

# ─── XDG user dirs ────────────────────────────────────────────────────────────
if command -v xdg-user-dirs-update &>/dev/null; then
  xdg-user-dirs-update
  echo "✓ XDG user dirs updated"
fi

echo ""
echo "✓ Niri desktop configured!"
echo ""
echo "  Display manager : SDDM (enabled)"
echo "  Session file    : /usr/share/wayland-sessions/niri.desktop"
echo "  SDDM config     : /etc/sddm.conf.d/10-wayland.conf"
echo "  Niri config     : ~/.config/niri/config.kdl"
echo "  TTY1 fallback   : ~/.zshrc (without exec)"
echo ""
echo "Keybinds (Super = Mod):"
echo "  Super+T / Enter   terminal"
echo "  Super+D           tofi launcher"
echo "  Super+E           thunar"
echo "  Super+B           firefox"
echo "  Super+Q           close window"
echo "  Super+F           maximize column"
echo "  Super+Space       toggle floating"
echo "  Super+R           cycle column width"
echo "  Super+1..9        switch workspace"
echo "  Super+Shift+1..9  move to workspace"
echo "  Print             screenshot"
echo "  Super+Shift+R     reload config"
echo "  Super+Shift+E     quit niri"
echo ""
echo "  → Reboot to start SDDM → select Niri session"
