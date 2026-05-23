#!/bin/bash
set -euo pipefail

echo "== Running Development Profile =="

# Development tools and languages
pacman -S --noconfirm \
    base-devel \
    git \
    github-cli \
    docker \
    docker-compose \
    nodejs \
    npm \
    python \
    python-pip \
    rustup \
    go \
    jq \
    ripgrep \
    fd \
    bat \
    fzf \
    tmux \
    neovim

# Enable Docker service
systemctl enable docker

echo "== Development Profile Complete =="
echo "Note: Add your user to 'docker' group: usermod -aG docker USERNAME"
