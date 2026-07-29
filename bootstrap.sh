#!/usr/bin/env bash
# Take a fresh Apple Silicon Mac from a clone to the declared configuration.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "This configuration supports macOS only."
[[ "$(uname -m)" == "arm64" ]] || die "This configuration currently supports Apple Silicon only."

say "Step 1/7: install Determinate Nix when missing"
if ! command -v nix >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
else
  say "Nix is already installed"
fi
NIX_BIN="$(command -v nix)"

say "Step 2/7: link this checkout to ~/.dotfiles"
if [[ -e "$HOME/.dotfiles" && ! -L "$HOME/.dotfiles" ]]; then
  die "$HOME/.dotfiles exists and is not a symlink; move it aside and rerun."
fi
ln -sfn "$DOTFILES_DIR" "$HOME/.dotfiles"

say "Step 3/7: personalize the configured username"
REAL_USER="$(id -un)"
FLAKE_USER="$(sed -nE 's/^[[:space:]]*user = "([^"]+)";.*/\1/p' "$DOTFILES_DIR/flake.nix" | head -n 1)"
[[ -n "$FLAKE_USER" ]] || die "Could not find the user setting in flake.nix."
if [[ "$FLAKE_USER" != "$REAL_USER" ]]; then
  printf 'flake.nix is configured for %s, but this Mac uses %s.\n' "$FLAKE_USER" "$REAL_USER"
  read -r -p "Rewrite flake.nix for $REAL_USER? [y/N] " REPLY
  [[ "$REPLY" == "y" || "$REPLY" == "Y" ]] || die "Update flake.nix before continuing."
  sed -i '' -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DOTFILES_DIR/flake.nix"
  say "Updated flake.nix; review and commit the username change."
fi

say "Step 4/7: update Homebrew and validate the flake"
"$DOTFILES_DIR/scripts/update-homebrew.sh"
"$NIX_BIN" flake check "$DOTFILES_DIR" --no-build

say "Step 5/7: preview strict Homebrew cleanup"
"$DOTFILES_DIR/scripts/homebrew-preflight.sh"

say "Step 6/7: apply the first nix-darwin build"
# Build darwin-rebuild from this flake's flake.lock-pinned nix-darwin input
# (the same reviewed source every later rebuild.sh uses) rather than fetching
# an unpinned branch ref live as root.
sudo "$NIX_BIN" run "$DOTFILES_DIR#darwinConfigurations.mac.config.system.build.darwin-rebuild" -- \
  switch --flake "$DOTFILES_DIR#mac"

say "Step 7/7: install user-scoped agent tools and verify"
"$DOTFILES_DIR/scripts/post-switch.sh"
"$DOTFILES_DIR/scripts/doctor.sh"

say "Done. Open a new terminal to pick up the complete shell environment."
