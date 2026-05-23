#!/bin/bash
set -euo pipefail

echo "== Running Minimal Profile =="

# Absolute minimum - just basic shell utilities
pacman -S --noconfirm \
    nano \
    htop \
    wget

echo "== Minimal Profile Complete =="
