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

if ! rg -q 'bun add --global --force @earendil-works/pi-coding-agent@latest' \
  scripts/post-switch.sh; then
  printf '%s\n' 'error: Pi must track the latest Bun release during rebuilds' >&2
  exit 1
fi

for json_file in home/.claude/settings.portable.json home/.config/opencode/package.json; do
  jq empty "$json_file"
done

if ! jq -e 'has("model") or has("effortLevel") | not' \
  home/.claude/settings.portable.json >/dev/null; then
  printf '%s\n' 'error: Claude portable settings contain machine-local model or effort' >&2
  exit 1
fi

if rg -n '^(model|model_reasoning_effort)[[:space:]]*=|^\[projects(?:\.|\])' \
  home/.codex/config.defaults.toml; then
  printf '%s\n' 'error: Codex portable defaults contain machine-local settings' >&2
  exit 1
fi

for mutable_config in \
  home/.claude/settings.json \
  home/.codex/config.toml \
  home/.pi/agent/settings.json \
  home/.pi/agent/models.json; do
  if [[ -e "$mutable_config" ]]; then
    printf 'error: mutable agent config is stored in the repository: %s\n' "$mutable_config" >&2
    exit 1
  fi
done

"$DOTFILES_DIR/scripts/test-materialize-agent-configs.sh"

"$DOTFILES_DIR/scripts/check-secrets.sh"

if command -v nix >/dev/null 2>&1; then
  nix flake check "$DOTFILES_DIR" --no-build
else
  printf '%s\n' 'warning: Nix is not installed; skipped flake evaluation' >&2
fi

printf '%s\n' 'static validation passed'
