#!/bin/bash
# KASPERENOK ZSH Remote Installer
# curl -sL https://raw.githubusercontent.com/kasper-studios/kzsh/main/install.sh | bash

set -e

REPO_URL="https://github.com/kasper-studios/kzsh"
INSTALL_DIR="$HOME/.config/kzsh"

print_color() {
  printf "\e[1;34m%s\e[0m\n" "$1"
}

# Helper to run commands with sudo if needed
run_cmd() {
  if [ "$EUID" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    "$@"
  fi
}

print_color "🚀 Starting KASPERENOK ZSH Remote Installation..."

# 1. Install basics if missing
if ! command -v git >/dev/null 2>&1 || ! command -v zsh >/dev/null 2>&1 || ! command -v which >/dev/null 2>&1; then
  print_color "📦 Installing base dependencies (git, zsh, which, curl, unzip)..."
  if [[ -f /etc/arch-release ]]; then
    run_cmd pacman -S --noconfirm git zsh which curl unzip
  elif [[ -f /etc/debian_version ]]; then
    run_cmd apt update && run_cmd apt install -y git zsh which curl unzip
  fi
fi

# 2. Clone or Update
REPO_DIR="$HOME/.kzsh-repo"

if [[ -d "$REPO_DIR/.git" ]]; then
  print_color "📂 Checking for updates..."
  cd "$REPO_DIR"
  
  # Fetch updates
  git fetch origin main --quiet 2>/dev/null || true
  
  # Check if updates available
  local_commit=$(git rev-parse HEAD 2>/dev/null)
  remote_commit=$(git rev-parse origin/main 2>/dev/null)
  
  if [[ "$local_commit" != "$remote_commit" ]]; then
    print_color "📥 Updates available, pulling..."
    git stash push -m "Auto-stash before update" --quiet 2>/dev/null || true
    git pull origin main
  else
    print_color "✅ Already up to date!"
  fi
else
  print_color "📂 Cloning repository..."
  # Remove old repo if exists but not a git repo
  if [[ -d "$REPO_DIR" ]] && [[ ! -d "$REPO_DIR/.git" ]]; then
    print_color "⚠️  Backing up old installation..."
    mv "$REPO_DIR" "$REPO_DIR.backup.$(date +%s)"
  fi
  
  # Clone entire repo to ~/.kzsh-repo
  git clone "$REPO_URL" "$REPO_DIR"
fi

# Create symlink from ~/.config/kzsh to repo's .config/kzsh
print_color "🔗 Creating symlink..."
mkdir -p "$HOME/.config"

# Remove old installation if it's not a symlink
if [[ -e "$INSTALL_DIR" ]] && [[ ! -L "$INSTALL_DIR" ]]; then
  print_color "⚠️  Backing up old ~/.config/kzsh..."
  mv "$INSTALL_DIR" "$INSTALL_DIR.backup.$(date +%s)"
fi

# Create symlink
ln -sf "$REPO_DIR/.config/kzsh" "$INSTALL_DIR"

# Copy .zshrc if it exists and user doesn't have one
if [[ -f "$REPO_DIR/.zshrc" ]] && [[ ! -f "$HOME/.zshrc" ]]; then
  cp "$REPO_DIR/.zshrc" "$HOME/.zshrc"
fi

# 3. Ensure entrypoint in .zshrc
if [[ ! -f "$HOME/.zshrc" ]]; then
  touch "$HOME/.zshrc"
fi
if ! grep -q "kzsh.zsh" "$HOME/.zshrc"; then
  print_color "🔗 Adding entrypoint to .zshrc..."
  cat >> "$HOME/.zshrc" << EOF

# KASPERENOK ZSH Entrypoint
export KZSH_DIR="\$HOME/.config/kzsh"
[[ -f "\$KZSH_DIR/kzsh.zsh" ]] && source "\$KZSH_DIR/kzsh.zsh"
EOF
fi

# 4. Set first_run flag in config
mkdir -p "$INSTALL_DIR"
if [[ ! -f "$INSTALL_DIR/config.yaml" ]]; then
  cp "$INSTALL_DIR/config.yaml.example" "$INSTALL_DIR/config.yaml" 2>/dev/null || \
  echo "first_run: yes" > "$INSTALL_DIR/config.yaml"
fi
# Force first_run if we just installed
sed -i 's/first_run: no/first_run: yes/g' "$INSTALL_DIR/config.yaml"

# 5. Change Shell
if [[ "$SHELL" != *"zsh"* ]]; then
  print_color "🐚 Changing shell to ZSH..."
  run_cmd chsh -s "$(command -v zsh)" "$USER"
fi

print_color "✨ Done! Restart your terminal to enjoy KASPERENOK ZSH."
print_color "💡 Or just run: zsh"
