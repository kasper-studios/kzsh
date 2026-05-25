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


# --- UPDATE (kupdate) ---
kupdate() {
  # Save current directory
  local original_dir="$PWD"
  
  print -P "\n%F{39}%B🔄 KZSH UPDATER%b%f"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Find the repo directory
  local repo_dir=""
  if [[ -L "${KZSH_DIR}" ]]; then
    # KZSH_DIR is a symlink, find the real repo
    local link_target=$(readlink "${KZSH_DIR}")
    if [[ "$link_target" == /* ]]; then
      # Absolute path
      repo_dir=$(cd "$(dirname "$link_target")/.." && pwd)
    else
      # Relative path
      repo_dir=$(cd "$(dirname "${KZSH_DIR}")/$link_target/.." && pwd)
    fi
  elif [[ -d "${KZSH_DIR}/.git" ]]; then
    # Old installation, KZSH_DIR itself is a git repo
    repo_dir="${KZSH_DIR}"
  elif [[ -d "$HOME/.kzsh-repo/.git" ]]; then
    # New installation, repo is in ~/.kzsh-repo
    repo_dir="$HOME/.kzsh-repo"
  else
    print -P "%F{red}✗ Not a git repository%f"
    print -P "%F{242}KZSH was not installed via git clone%f"
    return 1
  fi
  
  cd "$repo_dir" || return 1
  
  print -P "%F{242}Fetching updates from GitHub...%f"
  if ! git fetch origin main --quiet 2>/dev/null; then
    print -P "%F{red}✗ Failed to fetch updates%f"
    print -P "%F{242}Check your internet connection%f"
    cd "$original_dir"
    return 1
  fi
  
  local local_commit=$(git rev-parse HEAD 2>/dev/null)
  local remote_commit=$(git rev-parse origin/main 2>/dev/null)
  
  if [[ "$local_commit" == "$remote_commit" ]]; then
    print -P "%F{32}✓ KZSH is already up to date!%f"
    cd "$original_dir"
    return 0
  fi
  
  print -P "%F{39}Updates available!%f"
  print -P "%F{242}Local:  $local_commit%f"
  print -P "%F{242}Remote: $remote_commit%f"
  echo ""
  
  # Show what changed
  print -P "%F{39}Changes:%f"
  git log --oneline HEAD..origin/main | head -5
  echo ""
  
  read -q "?Update KZSH? [y/N] " || { echo ""; cd "$original_dir"; return 0; }
  echo ""
  
  # Stash local changes if any
  local has_changes=0
  if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    print -P "%F{yellow}⚠ Stashing local changes...%f"
    git stash push -m "Auto-stash before update $(date)" --quiet 2>/dev/null
    has_changes=1
  fi
  
  # Pull updates
  print -P "%F{242}Pulling updates...%f"
  if git pull origin main 2>&1 | tee /tmp/kzsh-update.log; then
    # Check for conflicts
    if grep -q "CONFLICT" /tmp/kzsh-update.log; then
      print -P "%F{red}✗ Merge conflicts detected!%f"
      print -P "%F{yellow}Conflicts:%f"
      git diff --name-only --diff-filter=U
      echo ""
      print -P "%F{242}Options:%f"
      print -P "  1. Resolve manually: cd $repo_dir && git status"
      print -P "  2. Abort and keep local: git merge --abort"
      print -P "  3. Accept remote: git checkout --theirs . && git add . && git commit"
      cd "$original_dir"
      return 1
    fi
    
    print -P "%F{32}✓ KZSH updated successfully!%f"
    
    # Pop stash if we stashed changes
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
    
    # Update last check time
    echo "$(date +%s)" > "${KZSH_DIR}/.last_update"
    
    # Clean up log
    rm -f /tmp/kzsh-update.log
  else
    print -P "%F{red}✗ Failed to update KZSH%f"
    print -P "%F{242}Try manually: cd $repo_dir && git pull%f"
    rm -f /tmp/kzsh-update.log
    cd "$original_dir"
    return 1
  fi
  
  # Return to original directory
  cd "$original_dir"
}
