#!/bin/bash
# KASPERENOK ZSH Remote Installer
# curl -sL https://raw.githubusercontent.com/kasper-studios/kzsh/main/install.sh | bash

set -e

REPO_URL="https://github.com/kasper-studios/kzsh"
INSTALL_DIR="$HOME/.config/kzsh"

print_color() { printf "\e[1;34m%s\e[0m\n" "$1"; }

run_cmd() {
  if [ "$EUID" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    "$@"
  fi
}

print_color "Starting KASPERENOK ZSH Remote Installation..."

# 1. Install basics if missing
if ! command -v git >/dev/null 2>&1 || ! command -v zsh >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  print_color "Installing base dependencies (git, zsh, curl)..."
  if [[ -f /etc/arch-release ]]; then
    run_cmd pacman -S --noconfirm git zsh curl
  elif [[ -f /etc/debian_version ]]; then
    run_cmd apt update && run_cmd apt install -y git zsh curl
  else
    echo "ERROR: Unsupported distribution. Please install git, zsh, curl manually."
    exit 1
  fi
fi

# Check ZSH version (minimum 5.0)
if command -v zsh >/dev/null 2>&1; then
  zsh_version=$(zsh --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
  zsh_major=$(echo "$zsh_version" | cut -d. -f1)
  [[ "$zsh_major" -lt 5 ]] && { echo "ERROR: ZSH version $zsh_version is too old (min 5.0)"; exit 1; }
fi

# 2. Clone or Update
REPO_DIR="$HOME/.kzsh-repo"

if [[ -d "$REPO_DIR/.git" ]]; then
  print_color "Checking for updates..."
  cd "$REPO_DIR"
  git fetch origin main --quiet 2>/dev/null || true
  local_commit=$(git rev-parse HEAD 2>/dev/null)
  remote_commit=$(git rev-parse origin/main 2>/dev/null)
  [[ "$local_commit" != "$remote_commit" ]] && {
    print_color "Updates available, pulling..."
    git stash push -m "Auto-stash" --quiet 2>/dev/null || true
    git pull origin main 2>/dev/null || git stash pop --quiet 2>/dev/null || true
  }
else
  print_color "Cloning repository..."
  [[ -d "$REPO_DIR" ]] && [[ ! -d "$REPO_DIR/.git" ]] && mv "$REPO_DIR" "$REPO_DIR.backup.$(date +%s)"
  git clone "$REPO_URL" "$REPO_DIR"
fi

# Create symlink
print_color "Creating symlink..."
mkdir -p "$HOME/.config"
[[ ! -d "$REPO_DIR/.config/kzsh" ]] && { echo "ERROR: Source directory not found"; exit 1; }
[[ -e "$INSTALL_DIR" ]] && [[ ! -L "$INSTALL_DIR" ]] && mv "$INSTALL_DIR" "$INSTALL_DIR.backup.$(date +%s)"
[[ -L "$INSTALL_DIR" ]] && [[ ! -e "$INSTALL_DIR" ]] && rm -f "$INSTALL_DIR"
ln -sf "$REPO_DIR/.config/kzsh" "$INSTALL_DIR"
[[ ! -L "$INSTALL_DIR" ]] && { echo "ERROR: Symlink not created"; exit 1; }

# Copy public directory to .config for web daemons
print_color "Setting up web daemon resources..."
[[ -d "$REPO_DIR/public" ]] && cp -rf "$REPO_DIR/public" "$REPO_DIR/.config/"

# Install Node.js dependencies if package.json exists
if [[ -f "$REPO_DIR/package.json" ]]; then
  print_color "Installing Node.js dependencies..."
  cd "$REPO_DIR"
  if command -v npm >/dev/null 2>&1; then
    npm install --silent 2>/dev/null || true
  fi
fi

# Copy .zshrc if needed
[[ -f "$REPO_DIR/.zshrc" ]] && [[ ! -f "$HOME/.zshrc" ]] && cp "$REPO_DIR/.zshrc" "$HOME/.zshrc"

# 3. Ensure entrypoint in .zshrc
[[ ! -f "$HOME/.zshrc" ]] && touch "$HOME/.zshrc"
if ! grep -q "kzsh.zsh" "$HOME/.zshrc"; then
  print_color "Adding entrypoint to .zshrc..."
  cat >> "$HOME/.zshrc" << 'EOF'

# KASPERENOK ZSH Entrypoint
export KZSH_DIR="$HOME/.config/kzsh"
[[ -f "$KZSH_DIR/kzsh.zsh" ]] && source "$KZSH_DIR/kzsh.zsh"
EOF
fi

print_color "Done! Restart your terminal to enjoy KASPERENOK ZSH."
print_color "Or just run: zsh"
