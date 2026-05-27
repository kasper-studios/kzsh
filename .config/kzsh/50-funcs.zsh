# ~/.config/kzsh/50-funcs.zsh
# Core Functions: kinstall, kdeps, khelp, search, mkproj

# --- HELPERS ---
clip() {
  if ! command -v clip.exe >/dev/null 2>&1; then
    print -P "%F{red}error:%f clip.exe not found (WSL only)"
    return 1
  fi
  cat "${1:-/dev/stdin}" | clip.exe
  print -P "📋 %F{green}Copied%f to Windows clipboard!"
}

search() {
  [[ -z "$1" ]] && { echo "usage: search <string>"; return 1; }
  if command -v rg >/dev/null 2>&1; then
    rg --color=always "$1" . | head -40 | bat --plain --color=always 2>/dev/null || rg --color=always "$1" . | head -40
  else
    grep -r --color=always "$1" . | head -40
  fi
}

mkproj() {
  local name="${1:-newproj}"
  mkdir -p ~/projects/"$name" && cd ~/projects/"$name"
  echo "# $name" > README.md
  [[ -x "$(command -v git)" ]] && git init >/dev/null 2>&1
  print -P "📦 %F{blue}Project $name created%f in ~/projects/$name"
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

  print -P "\n%F{39}%B🧪 kpreflight: base%b%f"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [[ "$do_install" == "yes" ]]; then
    print -P "%F{39}Installing base GUI stack (safe):%f %F{242}pciutils mesa vulkan-icd-loader%f"
    _kpreflight__sudo pacman -S --noconfirm --needed pciutils mesa vulkan-icd-loader >/dev/null 2>&1 || \
      print -P "%F{yellow}⚠ Failed to install some base packages (continuing).%f"
  fi

  if ! command -v lspci >/dev/null 2>&1; then
    print -P "%F{242}lspci not found (pciutils).%f"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    return 0
  fi

  local gpus
  gpus=$(lspci -nn | grep -Ei 'VGA compatible controller|3D controller|Display controller' || true)
  local gpu_count
  gpu_count=$(print -r -- "$gpus" | grep -c . 2>/dev/null || echo 0)

  print -P "%F{39}GPU devices detected:%f $gpu_count"
  if [[ -n "$gpus" ]]; then
    print -P "%F{242}$gpus%f"
  else
    print -P "%F{242}(no GPU lines detected via lspci)%f"
  fi

  if [[ "$gpu_count" -gt 1 ]]; then
    print -P "%F{yellow}⚠ Hybrid/multi-GPU detected.%f"
    print -P "%F{242}Wayland + hybrid NVIDIA/Optimus may require manual setup. No vendor drivers are installed automatically.%f"
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

_kpreflight_desktop() {
  print -P "\n%F{39}%B🧪 kpreflight: desktop%b%f"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Only checks/hints.
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files 2>/dev/null | grep -q '^sddm\.service'; then
      local enabled="no"
      systemctl is-enabled sddm.service >/dev/null 2>&1 && enabled="yes"
      print -P "%F{39}SDDM unit present:%f %F{242}(enabled: $enabled)%f"
    fi
  fi

  # Session entry checks (non-fatal)
  if [[ -d /usr/share/wayland-sessions ]]; then
    local niri_entry="/usr/share/wayland-sessions/niri.desktop"
    if [[ -f "$niri_entry" ]]; then
      print -P "%F{green}✓%f wayland session entry: %F{242}$niri_entry%f"
    else
      print -P "%F{242}No niri.desktop in /usr/share/wayland-sessions yet (will be created by desktop-niri hook).%f"
    fi
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Placeholders (minimal, to avoid future bloat)
_kpreflight_audio() { print -P "\n%F{39}%B🧪 kpreflight: audio%b%f"; print -P "%F{242}(not implemented yet)%f"; }
_kpreflight_gaming() { print -P "\n%F{39}%B🧪 kpreflight: gaming%b%f"; print -P "%F{242}(not implemented yet)%f"; }
_kpreflight_stream() { print -P "\n%F{39}%B🧪 kpreflight: stream%b%f"; print -P "%F{242}(not implemented yet)%f"; }
_kpreflight_network() { print -P "\n%F{39}%B🧪 kpreflight: network%b%f"; print -P "%F{242}(not implemented yet)%f"; }
_kpreflight_bluetooth() { print -P "\n%F{39}%B🧪 kpreflight: bluetooth%b%f"; print -P "%F{242}(not implemented yet)%f"; }

kpreflight() {
  local profile="${1:-base}"
  shift || true

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
      # Runs only what exists; still intentionally limited.
      _kpreflight_base "no"
      _kpreflight_desktop
      _kpreflight_audio
      _kpreflight_network
      _kpreflight_bluetooth
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

  print -P "\n%F{39}%B🔄 KZSH UPDATER%b%f"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  print -P "%F{242}Fetching updates from GitHub...%f"
  if ! git fetch origin main --quiet 2>/dev/null; then
    print -P "%F{red}✗ Failed to fetch updates%f"
    print -P "%F{242}Check your internet connection%f"
    return 1
  fi

  local local_commit=$(git rev-parse HEAD 2>/dev/null)
  local remote_commit=$(git rev-parse origin/main 2>/dev/null)

  if [[ "$local_commit" == "$remote_commit" ]]; then
    print -P "%F{32}✓ KZSH is already up to date!%f"
    return 0
  fi

  print -P "%F{39}Updates available!%f"
  print -P "%F{242}Local:  $local_commit%f"
  print -P "%F{242}Remote: $remote_commit%f"
  echo ""

  print -P "%F{39}Changes:%f"
  git log --oneline HEAD..origin/main | head -5
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
  if git pull origin main 2>&1 | tee /tmp/kzsh-update.log; then
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
