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
TMP_DIR=$(mktemp -d)
print_color "📂 Downloading repository..."
git clone "$REPO_URL" "$TMP_DIR"

print_color "📦 Installing files..."
mkdir -p "$INSTALL_DIR"
# Move contents from repo's .config/kzsh to ~/.config/kzsh
cp -r "$TMP_DIR/.config/kzsh/." "$INSTALL_DIR/"
# Move .zshrc if it exists in repo
[[ -f "$TMP_DIR/.zshrc" ]] && cp "$TMP_DIR/.zshrc" "$HOME/.zshrc"

rm -rf "$TMP_DIR"

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
