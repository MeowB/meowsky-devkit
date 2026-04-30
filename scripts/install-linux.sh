#!/usr/bin/env bash
set -euo pipefail

sudo apt update
sudo apt install -y \
  git \
  neovim \
  nodejs \
  npm \
  tmux \
  pandoc \
  xdg-utils

echo
echo "Open a new terminal before verifying the setup."
