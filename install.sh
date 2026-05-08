#!/bin/bash
# KASPERENOK ZSH Remote Installer
# curl -sL https://raw.githubusercontent.com/kasper-studios/kzsh/main/install.sh | bash

set -e

REPO_URL="https://github.com/kasper-studios/kzsh"
INSTALL_DIR="$HOME/.config/kzsh"

print_color() {
  printf "\e[1;34m%s\e[0m\n" "$1"
}

print_color "🚀 Starting KASPERENOK ZSH Remote Installation..."

# 1. Install basics if missing
if ! command -v git >/dev/null 2>&1 || ! command -v zsh >/dev/null 2>&1; then
  print_color "📦 Installing base dependencies (git, zsh)..."
  if [[ -f /etc/arch-release ]]; then
    sudo pacman -S --noconfirm git zsh curl unzip
  elif [[ -f /etc/debian_version ]]; then
    sudo apt update && sudo apt install -y git zsh curl unzip
  fi
fi

# 2. Clone or Update
if [[ -d "$INSTALL_DIR" ]]; then
  print_color "🔄 Existing installation found. Updating..."
  cd "$INSTALL_DIR" && git pull || true
else
  print_color "📂 Cloning repository..."
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

# 3. Setup .zshrc
if [[ -f "$HOME/.zshrc" && ! -L "$HOME/.zshrc" ]]; then
  print_color "📄 Backing up existing .zshrc..."
  mv "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%s)"
fi

print_color "🔗 Creating .zshrc entrypoint..."
cat > "$HOME/.zshrc" << EOF
# KASPERENOK ZSH Entrypoint
export KZSH_DIR="\$HOME/.config/kzsh"
[[ -f "\$KZSH_DIR/kzsh.zsh" ]] && source "\$KZSH_DIR/kzsh.zsh"
EOF

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
  sudo chsh -s "$(which zsh)" "$USER"
fi

print_color "✨ Done! Restart your terminal to enjoy KASPERENOK ZSH."
print_color "💡 Or just run: zsh"
