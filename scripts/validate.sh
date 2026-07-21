#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$DOTFILES_DIR"

for script in bootstrap.sh rebuild.sh scripts/*.sh; do
  bash -n "$script"
done

if rg -n '^[[:space:]]*npm[[:space:]]' bootstrap.sh rebuild.sh scripts/*.sh; then
  printf '%s\n' 'error: scripted npm calls must run through mise exec' >&2
  exit 1
fi

for json_file in home/.claude/settings.json home/.pi/agent/settings.json home/.pi/agent/models.json home/.config/opencode/package.json; do
  jq empty "$json_file"
done

"$DOTFILES_DIR/scripts/check-secrets.sh"

if command -v nix >/dev/null 2>&1; then
  nix flake check "$DOTFILES_DIR" --no-build
else
  printf '%s\n' 'warning: Nix is not installed; skipped flake evaluation' >&2
fi

printf '%s\n' 'static validation passed'
