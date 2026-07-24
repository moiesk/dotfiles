#!/usr/bin/env bash
# Guard the strict Homebrew cleanup with an explicit delta preview.
# Invoked by bootstrap.sh and by rebuild.sh before each darwin-rebuild switch.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

if ! command -v brew >/dev/null 2>&1; then
  printf '%s\n' "-- Homebrew is not installed yet; there is no existing inventory to remove."
  exit 0
fi

command -v nix >/dev/null 2>&1 || {
  printf '%s\n' "error: nix is required for the Homebrew preflight" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  printf '%s\n' "error: jq is required for the Homebrew preflight" >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

nix eval --json "$DOTFILES_DIR#darwinConfigurations.mac.config.homebrew.brews" \
  | jq -r '.[] | if type == "string" then . else .name end' \
  | sed -E 's#^.*/##' | sort -u > "$TMP_DIR/declared-formulae"
nix eval --json "$DOTFILES_DIR#darwinConfigurations.mac.config.homebrew.casks" \
  | jq -r '.[] | if type == "string" then . else .name end' \
  | sed -E 's#^.*/##' | sort -u > "$TMP_DIR/declared-casks"
nix eval --json "$DOTFILES_DIR#darwinConfigurations.mac.config.homebrew.taps" \
  | jq -r '.[] | if type == "string" then . else .name end' \
  | sort -u > "$TMP_DIR/declared-taps"

brew bundle dump --force --file="$TMP_DIR/current.Brewfile"
sed -nE 's/^brew "([^"]+)".*/\1/p' "$TMP_DIR/current.Brewfile" | sed -E 's#^.*/##' | sort -u > "$TMP_DIR/installed-formulae"
sed -nE 's/^cask "([^"]+)".*/\1/p' "$TMP_DIR/current.Brewfile" | sed -E 's#^.*/##' | sort -u > "$TMP_DIR/installed-casks"
sed -nE 's/^tap "([^"]+)".*/\1/p' "$TMP_DIR/current.Brewfile" | sort -u > "$TMP_DIR/installed-taps"

comm -23 "$TMP_DIR/installed-formulae" "$TMP_DIR/declared-formulae" > "$TMP_DIR/extra-formulae"
comm -23 "$TMP_DIR/installed-casks" "$TMP_DIR/declared-casks" > "$TMP_DIR/extra-casks"
comm -23 "$TMP_DIR/installed-taps" "$TMP_DIR/declared-taps" > "$TMP_DIR/extra-taps"

if [[ ! -s "$TMP_DIR/extra-formulae" && ! -s "$TMP_DIR/extra-casks" && ! -s "$TMP_DIR/extra-taps" ]]; then
  printf '%s\n' "==> No undeclared Homebrew leaves, casks, or taps were found."
  exit 0
fi

printf '%s\n' "WARNING: the strict Homebrew cleanup (cleanup = zap) will remove undeclared items."
if [[ -s "$TMP_DIR/extra-formulae" ]]; then
  printf '\nUndeclared formulae:\n'
  sed 's/^/  - /' "$TMP_DIR/extra-formulae"
fi
if [[ -s "$TMP_DIR/extra-casks" ]]; then
  printf '\nUndeclared casks:\n'
  sed 's/^/  - /' "$TMP_DIR/extra-casks"
fi
if [[ -s "$TMP_DIR/extra-taps" ]]; then
  printf '\nUndeclared taps:\n'
  sed 's/^/  - /' "$TMP_DIR/extra-taps"
fi

printf '\nAdd anything you want to keep to homebrew.nix before continuing.\n'
read -r -p 'Type WIPE UNDECLARED to allow strict cleanup: ' CONFIRM
[[ "$CONFIRM" == "WIPE UNDECLARED" ]] || {
  printf '%s\n' "Stopped before changing Homebrew."
  exit 1
}
