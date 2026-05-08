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

  # Phase 1: Mandatory Runtime
  echo "📦 Phase 1: Mandatory Runtime..."
  local mand_pkgs=$(kcfg get profile_mandatory)
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

  # Phase 3: System Profiles
  local layers=(core dev desktop media extra)
  for layer in "${layers[@]}"; do
    local pkgs=$(kcfg get "profile_$layer")
    if [[ -n "$pkgs" ]]; then
      echo ""
      print -P "📦 Profile %F{cyan}$layer%f contains: $pkgs"
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
