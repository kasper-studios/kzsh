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
    run_cmd pacman -S --noconfirm git zsh which curl unzip || {
      echo "ERROR: Failed to install dependencies"
      exit 1
    }
  elif [[ -f /etc/debian_version ]]; then
    run_cmd apt update && run_cmd apt install -y git zsh which curl unzip || {
      echo "ERROR: Failed to install dependencies"
      exit 1
    }
  else
    echo "ERROR: Unsupported distribution. Please install git, zsh, which, curl, unzip manually."
    exit 1
  fi
fi

# Check ZSH version (minimum 5.0)
if command -v zsh >/dev/null 2>&1; then
  zsh_version=$(zsh --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
  zsh_major=$(echo "$zsh_version" | cut -d. -f1)
  if [[ "$zsh_major" -lt 5 ]]; then
    echo "ERROR: ZSH version $zsh_version is too old. Minimum required: 5.0"
    exit 1
  fi
fi

# 2. Clone or Update
REPO_DIR="$HOME/.kzsh-repo"

if [[ -d "$REPO_DIR/.git" ]]; then
  print_color "📂 Checking for updates..."
  cd "$REPO_DIR" || {
    echo "ERROR: Cannot access $REPO_DIR"
    exit 1
  }
  
  # Fetch updates
  if ! git fetch origin main --quiet 2>/dev/null; then
    print_color "⚠️  Failed to fetch updates, continuing with local version..."
  else
    # Check if updates available
    local_commit=$(git rev-parse HEAD 2>/dev/null)
    remote_commit=$(git rev-parse origin/main 2>/dev/null)
    
    if [[ "$local_commit" != "$remote_commit" ]]; then
      print_color "📥 Updates available, pulling..."
      git stash push -m "Auto-stash before update" --quiet 2>/dev/null || true
      if ! git pull origin main 2>/dev/null; then
        print_color "⚠️  Failed to pull updates, continuing with local version..."
        git stash pop --quiet 2>/dev/null || true
      fi
    else
      print_color "✅ Already up to date!"
    fi
  fi
else
  print_color "📂 Cloning repository..."
  # Remove old repo if exists but not a git repo
  if [[ -d "$REPO_DIR" ]] && [[ ! -d "$REPO_DIR/.git" ]]; then
    print_color "⚠️  Backing up old installation..."
    mv "$REPO_DIR" "$REPO_DIR.backup.$(date +%s)"
  fi
  
  # Clone entire repo to ~/.kzsh-repo
  if ! git clone "$REPO_URL" "$REPO_DIR"; then
    echo "ERROR: Failed to clone repository from $REPO_URL"
    echo "Please check your internet connection and try again."
    exit 1
  fi
fi

# Create symlink from ~/.config/kzsh to repo's .config/kzsh
print_color "🔗 Creating symlink..."
mkdir -p "$HOME/.config"

# Verify source directory exists
if [[ ! -d "$REPO_DIR/.config/kzsh" ]]; then
  echo "ERROR: Source directory $REPO_DIR/.config/kzsh not found"
  echo "Repository structure may be corrupted. Try removing $REPO_DIR and running again."
  exit 1
fi

# Remove old installation if it's not a symlink
if [[ -e "$INSTALL_DIR" ]] && [[ ! -L "$INSTALL_DIR" ]]; then
  print_color "⚠️  Backing up old ~/.config/kzsh..."
  mv "$INSTALL_DIR" "$INSTALL_DIR.backup.$(date +%s)"
fi

# Remove broken symlink if exists
if [[ -L "$INSTALL_DIR" ]] && [[ ! -e "$INSTALL_DIR" ]]; then
  print_color "🔧 Removing broken symlink..."
  rm -f "$INSTALL_DIR"
fi

# Create symlink
if ! ln -sf "$REPO_DIR/.config/kzsh" "$INSTALL_DIR"; then
  echo "ERROR: Failed to create symlink"
  exit 1
fi

# Verify symlink was created correctly
if [[ ! -L "$INSTALL_DIR" ]]; then
  echo "ERROR: Symlink was not created"
  exit 1
fi

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
# Config is already available via symlink, just ensure first_run is set
if [[ -f "$INSTALL_DIR/config.yaml" ]]; then
  # Use sed with backup for cross-platform compatibility
  if sed --version 2>&1 | grep -q GNU; then
    # GNU sed
    sed -i 's/first_run: no/first_run: yes/g' "$INSTALL_DIR/config.yaml"
  else
    # BSD sed (macOS)
    sed -i '' 's/first_run: no/first_run: yes/g' "$INSTALL_DIR/config.yaml"
  fi
else
  # Create minimal config if it doesn't exist
  echo "first_run: yes" > "$INSTALL_DIR/config.yaml"
  echo "auto_start_session: yes" >> "$INSTALL_DIR/config.yaml"
  echo "auto_update: yes" >> "$INSTALL_DIR/config.yaml"
fi

# 5. Change Shell
if [[ "$SHELL" != *"zsh"* ]]; then
  print_color "🐚 Changing shell to ZSH..."
  zsh_path=$(command -v zsh)
  if [[ -z "$zsh_path" ]]; then
    echo "ERROR: ZSH not found in PATH"
    exit 1
  fi
  
  # Check if zsh is in /etc/shells
  if ! grep -q "^$zsh_path$" /etc/shells 2>/dev/null; then
    print_color "⚠️  Adding ZSH to /etc/shells..."
    echo "$zsh_path" | run_cmd tee -a /etc/shells >/dev/null
  fi
  
  if ! run_cmd chsh -s "$zsh_path" "$USER"; then
    print_color "⚠️  Failed to change shell automatically."
    print_color "💡 Run manually: chsh -s $zsh_path"
  fi
fi

print_color "✨ Done! Restart your terminal to enjoy KASPERENOK ZSH."
print_color "💡 Or just run: zsh"
