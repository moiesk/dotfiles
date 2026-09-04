#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
NIX_BIN="${NIX_BIN:-nix}"

if ! command -v "$NIX_BIN" >/dev/null 2>&1; then
  printf '%s\n' 'warning: Nix is not installed; skipped lavish-axi managed environment evaluation' >&2
  exit 0
fi

managed_hosts="$($NIX_BIN eval --json \
  --apply 'users: builtins.mapAttrs (_: userConfig: userConfig.home.sessionVariables.LAVISH_AXI_HOST or null) users' \
  "$DOTFILES_DIR#darwinConfigurations.mac.config.home-manager.users")"
if ! jq -e 'length > 0 and all(.[]; . == "127.0.0.1")' <<<"$managed_hosts" >/dev/null; then
  printf '%s\n' 'error: every managed user must set LAVISH_AXI_HOST to 127.0.0.1' >&2
  exit 1
fi

printf '%s\n' 'lavish-axi managed host is enforced'
