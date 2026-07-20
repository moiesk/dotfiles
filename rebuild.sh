#!/usr/bin/env bash
# Reapply the configuration after editing the repository.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [[ -e "$HOME/.dotfiles" && ! -L "$HOME/.dotfiles" ]]; then
  printf 'error: %s exists and is not a symlink\n' "$HOME/.dotfiles" >&2
  exit 1
fi

ln -sfn "$DOTFILES_DIR" "$HOME/.dotfiles"

if ! command -v darwin-rebuild >/dev/null 2>&1; then
  printf 'error: darwin-rebuild is missing; run ./bootstrap.sh first\n' >&2
  exit 1
fi

printf '==> applying nix-darwin configuration\n'
sudo darwin-rebuild switch --flake "$DOTFILES_DIR#mac"

"$DOTFILES_DIR/scripts/post-switch.sh"
"$DOTFILES_DIR/scripts/doctor.sh"
