#!/usr/bin/env bash
# Refresh the Homebrew interpreter before current package definitions use it.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

printf '==> updating the locked Homebrew source\n'
nix flake update brew-src --flake "$DOTFILES_DIR"
