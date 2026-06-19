# ~/.config/kzsh/50-funcs.zsh
# Core Functions: kinstall, kdeps, khelp, search, mkproj

# --- HELPERS ---
clip() {
    if command -v wl-copy >/dev/null 2>&1; then
        wl-copy < "$1"
    elif command -v xclip >/dev/null 2>&1; then
        xclip -selection clipboard < "$1"
    elif command -v clip.exe >/dev/null 2>&1; then
        clip.exe < "$1"
    else
        echo "No clipboard backend found"
        return 1
    fi
}

search() {
  [[ -z "$1" ]] && { echo "usage: search <string>"; return 1; }
   if command -v rg >/dev/null 2>&1; then
     rg --color=always -F "$1" . | head -40 | bat --plain --color=always 2>/dev/null || rg --color=always -F "$1" . | head -40
   else
     grep -r --color=always -F "$1" . | head -40
   fi
}

mkproj() {
  local name="${1:-newproj}"
  mkdir -p ~/Desktop/projects/"$name" && cd ~/Desktop/projects/"$name"
  echo "# $name" > README.md
  [[ -x "$(command -v git)" ]] && git init >/dev/null 2>&1
  print -P "📦 %F{blue}Project $name created%f in ~/Desktop/projects/$name"
  ls
}

# --- INSTALLER (kinstall) ---
kinstall() {
  echo ""
  print -P "%F{39}%B🚀 KZSH INSTALLER%b%f"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  print -P "Detected distro: %F{cyan}$KZSH_DISTRO%f"
  echo ""

  # Phase 0: AUR helper (Arch only)
  if [[ "$KZSH_DISTRO" == "arch" || "$KZSH_DISTRO" == "manjaro" || "$KZSH_DISTRO" == "endeavouros" ]]; then
    if ! command -v yay >/dev/null 2>&1 && ! command -v paru >/dev/null 2>&1; then
      echo ""
      print -P "📦 Phase 0: Installing %F{cyan}yay%f (AUR helper)..."
      local tmp_yay=$(mktemp -d)
      git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$tmp_yay" && \
        (cd "$tmp_yay" && makepkg -si --noconfirm) && \
        rm -rf "$tmp_yay" && \
        print -P "✅ %F{green}yay installed!%f" || \
        print -P "%F{red}✗ yay install failed, continuing without AUR helper%f"
    else
      print -P "✅ AUR helper already present, skipping."
    fi
  fi

  # Phase 1: Mandatory Runtime (distro-specific)
  echo "📦 Phase 1: Mandatory Runtime..."
  local mand_pkgs=$(kcfg get "profile_${KZSH_DISTRO}_mandatory")
  if [[ -z "$mand_pkgs" ]]; then
    mand_pkgs=$(kcfg get "profile_mandatory")
  fi
  local to_install=()
  
  for p in ${=mand_pkgs}; do
    if ! kpkg check "$p"; then to_install+=("$p"); fi
  done

  if [[ ${#to_install[@]} -gt 0 ]]; then
    print -P "Installing mandatory: %F{yellow}${to_install[*]}%f"
    kpkg install "${to_install[@]}"
  else
    echo "✅ Runtime core already present."
  fi

  # Phase 2: Fonts
  if ! fc-list | grep -qi "nerd\|jetbrains" >/dev/null 2>&1; then
    echo ""
    read -q "ans?🔤 Install JetBrains Mono Nerd Font? [y/N] "
    echo ""
    [[ "$ans" == [yY] ]] && kzsh_install_fonts
  fi

  # Phase 3: System Profiles (distro-specific)
  local layers=(core dev desktop media extra)
  for layer in "${layers[@]}"; do
    local prof_name="profile_${KZSH_DISTRO}_${layer}"
    local pkgs=$(kcfg get "$prof_name")
    if [[ -z "$pkgs" ]]; then
      prof_name="profile_${layer}"
      pkgs=$(kcfg get "$prof_name")
    fi
    
    if [[ -n "$pkgs" ]]; then
      echo ""
      print -P "📦 Profile %F{cyan}$layer%f (%F{242}$KZSH_DISTRO%f) contains: $pkgs"
      read -q "ans?Install this profile? [y/N] "
      echo ""
      if [[ "$ans" == [yY] ]]; then
        kpkg install "$layer"
      fi
    fi
  done

  kcfg set first_run "no"
  echo ""
  print -P "%F{green}%B🎉 Setup complete!%b%f Use 'krl' to refresh."
}

# --- PREFLIGHT (kpreflight) ---
# Preflight is intentionally profile-based to avoid a huge "check the whole universe" command.
# Use: kpreflight base|desktop|audio|gaming|stream|network|bluetooth|doctor
# Only 'base' may install safe packages (pciutils/mesa/vulkan loader). Everything else is checks/hints.

_kpreflight__is_archish() {
  [[ "$KZSH_DISTRO" == "arch" || "$KZSH_DISTRO" == "manjaro" || "$KZSH_DISTRO" == "endeavouros" ]]
}

_kpreflight__sudo() {
  if [[ "$EUID" -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    "$@"
  fi
}

_kpreflight_base() {
  local do_install="$1"  # yes|no

  if [[ "$do_install" == "yes" ]]; then
    print -P "%F{39}Installing base GUI stack (safe):%f %F{242}pciutils mesa vulkan-icd-loader%f"
    _kpreflight__sudo pacman -S --noconfirm --needed pciutils mesa vulkan-icd-loader >/dev/null 2>&1 || \
      print -P "%F{yellow}⚠ Failed to install some base packages (continuing).%f"
  fi

  # Check for GPU
  if ! command -v lspci >/dev/null 2>&1; then
    print -P "%F{red}✗%f lspci not found (pciutils missing)"
    return 0
  fi

  local gpus
  gpus=$(lspci -nn | grep -Ei 'VGA compatible controller|3D controller|Display controller' || true)
  local gpu_count
  gpu_count=$(print -r -- "$gpus" | grep -c . 2>/dev/null || echo 0)

  if [[ "$gpu_count" -gt 0 ]]; then
    print -P "%F{green}✓%f GPU detected"
  else
    print -P "%F{red}✗%f GPU not detected"
  fi

  # Check for session
  if [[ -n "$XDG_SESSION_TYPE" ]]; then
    print -P "%F{green}✓%f Session detected ($XDG_SESSION_TYPE)"
  else
    # Try to detect session type from logind
    if loginctl show-session "$(loginctl | grep $(whoami) | awk '{print $1}')" -p Type --value 2>/dev/null | grep -q .; then
      print -P "%F{green}✓%f Session detected (via logind)"
    else
      print -P "%F{red}✗%f Session not detected"
    fi
  fi
}

_kpreflight_desktop() {
  # SDDM unit
  if [ -f /usr/lib/systemd/system/sddm.service ]; then
    print -P "%F{green}✓%f SDDM unit present"
    if systemctl is-enabled sddm.service >/dev/null 2>&1; then
      print -P "%F{green}✓%f SDDM unit enabled"
    else
      print -P "%F{yellow}⚠%f SDDM unit disabled"
    fi
  else
    print -P "%F{red}✗%f SDDM unit missing"
  fi

  # Niri desktop entry
  if [ -f /usr/share/wayland-sessions/niri.desktop ]; then
    print -P "%F{green}✓%f Niri desktop entry present"
  else
    print -P "%F{red}✗%f Niri desktop entry missing"
  fi
}

# Placeholders (minimal, to avoid future bloat)
_kpreflight_audio() {
  # PipeWire (user service)
  if systemctl --user is-active pipewire.service >/dev/null 2>&1; then
    print -P "%F{green}✓%f pipewire.service"
  else
    print -P "%F{red}✗%f pipewire.service"
  fi

  # WirePlumber (user service)
  if systemctl --user is-active wireplumber.service >/dev/null 2>&1; then
    print -P "%F{green}✓%f wireplumber.service"
  else
    print -P "%F{red}✗%f wireplumber.service"
  fi

  # ALSA
  if [ -d /proc/asound ] && [ "$(ls -A /proc/asound 2>/dev/null)" ]; then
    print -P "%F{green}✓%f ALSA devices found"
  else
    print -P "%F{red}✗%f ALSA no devices found"
  fi

  # PulseAudio compatibility (pactl)
  if ! command -v pactl >/dev/null 2>&1; then
    print -P "%F{yellow}⚠%f pactl not found"
  elif ! pactl info >/dev/null 2>&1; then
    print -P "%F{red}✗%f pactl failed"
  else
    print -P "%F{green}✓%f PulseAudio compatibility (pactl)"
  fi
}
_kpreflight_gaming() {
  # Vulkan support
  if [ -d /usr/share/vulkan/icd.d ] && [ "$(ls -A /usr/share/vulkan/icd.d 2>/dev/null)" ]; then
    print -P "%F{green}✓%f Vulkan support"
  else
    print -P "%F{red}✗%f Vulkan support missing"
  fi

  # Mesa drivers
  if command -v glxinfo >/dev/null 2>&1; then
    if glxinfo | grep -qi "mesa"; then
      print -P "%F{green}✓%f Mesa drivers"
    else
      print -P "%F{yellow}⚠%f Non-Mesa OpenGL renderer"
    fi
  else
    # glxinfo not installed, try to check via package
    if kpkg check mesa >/dev/null 2>&1; then
      print -P "%F{green}✓%f Mesa drivers (installed)"
    else
      print -P "%F{red}✗%f Mesa drivers not installed"
    fi
  fi

  # GPU drivers (from lspci, we can check if the driver module is loaded)
  # We'll reuse the GPU detection from base, but we don't have that info here.
  # Instead, we can check for the presence of kernel modules for common drivers.
  # This is a simplified check: if we have a GPU (from lspci) and the driver is loaded.
  # We'll skip for now and just note that we checked GPU in base.
  print -P "%F{blue}ℹ%f GPU drivers: see kpreflight base output"

  # gamemode: check for gamemoded (daemon) or gamemoderun (command)
  if systemctl --user is-active gamemoded >/dev/null 2>&1 || command -v gamemoderun >/dev/null 2>&1; then
    print -P "%F{green}✓%f gamemode available"
  else
    print -P "%F{red}✗%f gamemode missing"
  fi

  # mangohud
  if command -v mangohud >/dev/null 2>&1; then
    print -P "%F{green}✓%f mangohud available"
  else
    print -P "%F{red}✗%f mangohud missing"
  fi
}
_kpreflight_stream() {
  # OBS Studio
  if command -v obs >/dev/null 2>&1; then
    print -P "%F{green}✓%f OBS Studio available"
  else
    print -P "%F{red}✗%f OBS Studio missing"
  fi

# PipeWire (for streaming, we need PipeWire)
   if systemctl --user is-active pipewire.service >/dev/null 2>&1; then
     print -P "%F{green}✓%f PipeWire running"
   else
     print -P "%F{red}✗%f PipeWire not running"
   fi

# xdg-desktop-portal
   if systemctl --user is-active xdg-desktop-portal.service >/dev/null 2>&1; then
     print -P "%F{green}✓%f xdg-desktop-portal active"
   else
     print -P "%F{red}✗%f xdg-desktop-portal inactive"
   fi

  # Screen capture capability (check if xdg-desktop-portal has a backend)
  # We'll check for the presence of a backend: xdg-desktop-portal-wlr or xdg-desktop-portal-gnome
  if command -v xdg-desktop-portal >/dev/null 2>&1; then
    # Actually, we want to check if the service is active and if there is a backend installed.
    # We'll check for common backends.
    if [ -d /usr/share/xdg-desktop-portal/portals ] && [ "$(ls -A /usr/share/xdg-desktop-portal/portals 2>/dev/null)" ]; then
      print -P "%F{green}✓%f Screen capture capable (backend available)"
    else
      print -P "%F{yellow}⚠%f xdg-desktop-portal active but no backend detected"
    fi
  else
    print -P "%F{red}✗%f xdg-desktop-portal missing"
  fi
}
_kpreflight_network() {
  # NetworkManager
  if systemctl is-active NetworkManager.service >/dev/null 2>&1; then
    print -P "%F{green}✓%f NetworkManager active"
  else
    print -P "%F{red}✗%f NetworkManager inactive"
  fi

  # nmcli
  if command -v nmcli >/dev/null 2>&1; then
    print -P "%F{green}✓%f nmcli available"
  else
    print -P "%F{red}✗%f nmcli missing"
  fi

   # Internet connectivity
   # Try to curl to archlinux.org with a timeout, if curl is available.
   # Otherwise, try to open a TCP connection to 8.8.8.8:53 (DNS) or 1.1.1.1:53.
   if command -v curl >/dev/null 2>&1; then
     if timeout 5 bash -c "</dev/tcp/archlinux.org/443" 2>/dev/null; then
       print -P "%F{green}✓%f internet reachable"
     else
       print -P "%F{red}✗%f internet unreachable"
     fi
   else
    # Fallback: try to open TCP connection to 8.8.8.8:53
    if timeout 3 bash -c "echo >/dev/tcp/8.8.8.8/53" 2>/dev/null; then
      print -P "%F{green}✓%f internet reachable (TCP to 8.8.8.8:53)"
    elif timeout 3 bash -c "echo >/dev/tcp/1.1.1.1/53" 2>/dev/null; then
      print -P "%F{green}✓%f internet reachable (TCP to 1.1.1.1:53)"
    else
      print -P "%F{red}✗%f internet unreachable"
    fi
  fi

  # DNS resolve
  # Try to resolve archlinux.org using getent, drill, or nslookup
  resolved=0
  if command -v getent >/dev/null 2>&1; then
    if getent hosts archlinux.org >/dev/null 2>&1; then
      resolved=1
    fi
  elif command -v drill >/dev/null 2>&1; then
    if drill archlinux.org >/dev/null 2>&1; then
      resolved=1
    fi
  elif command -v nslookup >/dev/null 2>&1; then
    if nslookup archlinux.org >/dev/null 2>&1; then
      resolved=1
    fi
  fi

  if [ $resolved -eq 1 ]; then
    print -P "%F{green}✓%f DNS resolve (archlinux.org)"
  else
    print -P "%F{red}✗%f DNS resolve failed"
  fi
}
_kpreflight_bluetooth() {
  # Bluetooth service
  if systemctl is-active bluetooth.service >/dev/null 2>&1; then
    print -P "%F{green}✓%f Bluetooth service"
  else
    print -P "%F{red}✗%f Bluetooth service inactive"
  fi

  # bluetoothctl
  if command -v bluetoothctl >/dev/null 2>&1; then
    print -P "%F{green}✓%f bluetoothctl available"
  else
    print -P "%F{red}✗%f Bluetooth CLI unavailable
package: bluez-utils"
  fi

  # Adapter present
  if command -v bluetoothctl >/dev/null 2>&1; then
    if bluetoothctl show | grep -q "Powered: yes"; then
      print -P "%F{green}✓%f Adapter present and powered"
    elif bluetoothctl list | grep -q "Controller"; then
      print -P "%F{yellow}⚠%f Adapter present but powered off"
    else
      print -P "%F{red}✗%f No adapter detected"
    fi
  else
    # bluetoothctl missing, skip adapter check
    :
  fi
}

kpreflight() {
  local profile="${1:-base}"
  if [[ $# -gt 0 ]]; then
    shift
  fi

  if ! _kpreflight__is_archish; then
    print -P "%F{242}kpreflight: skipping (unsupported distro: $KZSH_DISTRO)%f"
    return 0
  fi

  case "$profile" in
    base)
      local do_install="no"
      [[ "${1:-}" == "--install" ]] && do_install="yes"
      _kpreflight_base "$do_install"
      ;;
    desktop)
      _kpreflight_desktop
      ;;
    audio)
      _kpreflight_audio
      ;;
    gaming)
      _kpreflight_gaming
      ;;
    stream)
      _kpreflight_stream
      ;;
    network)
      _kpreflight_network
      ;;
    bluetooth)
      _kpreflight_bluetooth
      ;;
    doctor)
      # Runs all checks
      _kpreflight_base "no"
      _kpreflight_desktop
      _kpreflight_audio
      _kpreflight_network
      _kpreflight_bluetooth
      _kpreflight_gaming
      _kpreflight_stream
      ;;
    *)
      echo "usage: kpreflight base [--install] | desktop | audio | gaming | stream | network | bluetooth | doctor"
      return 1
      ;;
  esac
}

# --- DEPENDENCIES (kdeps) ---
KZSH_DEPS=(
  "bat:📄 Syntax highlighting"
  "lsd:📁 Modern ls"
  "ripgrep:🔍 Fast search (rg)"
  "git:🐙 Git"
  "fzf:🎯 Fuzzy finder"
  "zoxide:🚀 Smart cd"
  "neovim:⚡ Neovim"
)

kdeps() {
  if [[ "$1" == "install" ]]; then
    kinstall
    return
  fi

  echo ""
  print -P "%F{39}%B📦 KZSH DEPENDENCIES%b%f"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  for item in "${KZSH_DEPS[@]}"; do
    local cmd="${item%%:*}"
    local desc="${item#*:}"
    if kpkg check "$cmd"; then
      print -P "%F{green}✓ %-12s%f $desc" "$cmd"
    else
      print -P "%F{red}✗ %-12s%f $desc" "$cmd"
    fi
  done
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  print -P "💡 Run %F{yellow}kinstall%f to fix missing deps."
}

# --- SMART HANDLER ---
command_not_found_handler() {
  local cmd="$1"
  local pkg="$cmd"
  
  [[ "$cmd" == "rg" ]] && pkg="ripgrep"
  [[ "$cmd" == "bat" && "$KZSH_DISTRO" == "ubuntu" ]] && pkg="bat" # Note: on some it's 'batcat'

  echo "[kzsh] Command '$cmd' not found."
  read -q "ans?Try installing '$pkg'? [y/N] "
  echo ""
  if [[ "$ans" == [yY] ]]; then
    kpkg install "$pkg"
    return $?
  fi
  return 127
}

# --- FONT INSTALLER ---
kzsh_install_fonts() {
  local font_dir="$HOME/.local/share/fonts"
  mkdir -p "$font_dir"
  local url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
  echo "⬇️ Downloading JetBrains Mono Nerd Font..."
  curl -L -o /tmp/font.zip "$url"
  unzip -o /tmp/font.zip -d "$font_dir" >/dev/null
  fc-cache -fv >/dev/null 2>&1
  print -P "✅ %F{green}Fonts installed!%f Set your terminal to JetBrainsMono NF."
}

# --- CHEAT SHEET ---
khelp() {
  cat << 'HELP' | bat --plain --language=help 2>/dev/null || cat
KASPERENOK ZSH CHEAT SHEET

PROJECTS:
  proj [name]   -> go to projects (mk if missing)
  mkproj NAME   -> create project scaffold
  clip [file]   -> copy to Windows clipboard

KZSH UTILS:
  kpkg install  -> distro-agnostic install
  ksys list/log -> systemd management
  kapp add/list -> custom command shortcuts
  kstart add    -> manage autostart commands
  kcfg edit     -> open config in $EDITOR
  kcfg get/set  -> manual config edit

SYSTEM:
  update        -> sync & upgrade system
  krl           -> reload zsh
  kdeps         -> check dependencies
  kinstall      -> run full setup
HELP
}


kupdate() {
   local repo_dir=$(kzsh_repo_dir)
   [[ -z "$repo_dir" ]] && {
     print -P "%F{red}✗ Not a git repository%f"
     print -P "%F{242}KZSH was not installed via git clone%f"
     return 1
   }
   cd "$repo_dir" || { print -P "%F{red}✗ Cannot cd into repo dir%f"; return 1; }

  print -P "\n%F{39}%B🔄 KZSH UPDATER%b%f"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
   print -P "%F{242}Fetching updates from GitHub...%f"
   local current_branch=$(git branch --show-current 2>/dev/null)
   [[ -z "$current_branch" ]] && { print -P "%F{red}✗ Could not determine current branch%f"; return 1; }
   if ! git fetch origin $current_branch --quiet 2>/dev/null; then
    print -P "%F{red}✗ Failed to fetch updates%f"
    print -P "%F{242}Check your internet connection%f"
    return 1
  fi

   local local_commit=$(git rev-parse HEAD 2>/dev/null)
   local remote_commit=$(git rev-parse origin/$current_branch 2>/dev/null)

  if [[ "$local_commit" == "$remote_commit" ]]; then
    print -P "%F{32}✓ KZSH is already up to date!%f"
    return 0
  fi

  print -P "%F{39}Updates available!%f"
  print -P "%F{242}Local:  $local_commit%f"
  print -P "%F{242}Remote: $remote_commit%f"
  echo ""

   print -P "%F{39}Changes:%f"
   git log --oneline HEAD..origin/$current_branch | head -5
  echo ""

  read -q "?Update KZSH? [y/N] " || { echo ""; return 0; }
  echo ""

  local has_changes=0
  if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    print -P "%F{yellow}⚠ Stashing local changes...%f"
    git stash push -m "Auto-stash before update $(date)" --quiet 2>/dev/null
    has_changes=1
  fi

   print -P "%F{242}Pulling updates...%f"
   if git pull origin $current_branch 2>&1 | tee /tmp/kzsh-update.log; then
    if grep -q "CONFLICT" /tmp/kzsh-update.log; then
      print -P "%F{red}✗ Merge conflicts detected!%f"
      print -P "%F{yellow}Conflicts:%f"
      git diff --name-only --diff-filter=U
      echo ""
      print -P "%F{242}Options:%f"
      print -P "  1. Resolve manually: cd $repo_dir && git status"
      print -P "  2. Abort and keep local: git merge --abort"
      print -P "  3. Accept remote: git checkout --theirs . && git add . && git commit"
      return 1
    fi
    print -P "%F{32}✓ KZSH updated successfully!%f"
    if [[ $has_changes -eq 1 ]]; then
      echo ""
      print -P "%F{yellow}⚠ Restoring your local changes...%f"
      if git stash pop --quiet 2>/dev/null; then
        print -P "%F{32}✓ Local changes restored%f"
      else
        print -P "%F{red}⚠ Conflicts detected, check 'git stash list'%f"
        print -P "%F{242}Your changes are saved in stash. Resolve conflicts manually.%f"
      fi
    fi
    echo ""
    print -P "%F{39}Restart your shell to apply changes:%f"
    print -P "%F{242}  exec zsh%f"
    echo ""
    echo "$(date +%s)" > "${KZSH_DIR}/.last_update"
    rm -f /tmp/kzsh-update.log
  else
    print -P "%F{red}✗ Failed to update KZSH%f"
    print -P "%F{242}Try manually: cd $repo_dir && git pull%f"
    rm -f /tmp/kzsh-update.log
    return 1
  fi
}
