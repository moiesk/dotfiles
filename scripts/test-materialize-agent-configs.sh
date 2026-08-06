#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

assert_json_value() {
  local file="$1" filter="$2" expected="$3" actual
  actual="$(jq -r "$filter" "$file")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'expected %s in %s, got %s\n' "$expected" "$file" "$actual" >&2
    exit 1
  fi
}

# A fresh home gets portable Claude and Pi settings. Codex and Pi's model
# catalog remain absent until their harnesses need mutable local configuration.
HOME="$TEST_ROOT/fresh-home" \
  "$DOTFILES_DIR/scripts/materialize-agent-configs.sh" "$DOTFILES_DIR" "$(command -v jq)"
assert_json_value "$TEST_ROOT/fresh-home/.claude/settings.json" '.theme' 'auto'
[[ ! -e "$TEST_ROOT/fresh-home/.codex/config.toml" ]]
assert_json_value "$TEST_ROOT/fresh-home/.pi/agent/settings.json" '.theme' 'light/dark'
[[ ! -e "$TEST_ROOT/fresh-home/.pi/agent/models.json" ]]

# Existing machine-local selections survive while portable keys are restored.
mkdir -p "$TEST_ROOT/existing-home/.claude" "$TEST_ROOT/existing-home/.pi/agent"
printf '%s\n' '{"theme":"dark","model":"local-model","effortLevel":"high"}' \
  > "$TEST_ROOT/existing-home/.claude/settings.json"
printf '%s\n' \
  '{"theme":"light","defaultProvider":"local-provider","defaultModel":"local-model","defaultThinkingLevel":"high"}' \
  > "$TEST_ROOT/existing-home/.pi/agent/settings.json"
HOME="$TEST_ROOT/existing-home" \
  "$DOTFILES_DIR/scripts/materialize-agent-configs.sh" "$DOTFILES_DIR" "$(command -v jq)"
assert_json_value "$TEST_ROOT/existing-home/.claude/settings.json" '.theme' 'auto'
assert_json_value "$TEST_ROOT/existing-home/.claude/settings.json" '.model' 'local-model'
assert_json_value "$TEST_ROOT/existing-home/.claude/settings.json" '.effortLevel' 'high'
assert_json_value "$TEST_ROOT/existing-home/.pi/agent/settings.json" '.theme' 'light/dark'
assert_json_value "$TEST_ROOT/existing-home/.pi/agent/settings.json" '.defaultProvider' 'local-provider'
assert_json_value "$TEST_ROOT/existing-home/.pi/agent/settings.json" '.defaultModel' 'local-model'
assert_json_value "$TEST_ROOT/existing-home/.pi/agent/settings.json" '.defaultThinkingLevel' 'high'

# Legacy managed symlinks become independent mutable files.
mkdir -p "$TEST_ROOT/linked-home/.claude" "$TEST_ROOT/legacy"
printf '%s\n' '{"model":"linked-model"}' > "$TEST_ROOT/legacy/settings.json"
ln -s "$TEST_ROOT/legacy/settings.json" "$TEST_ROOT/linked-home/.claude/settings.json"
HOME="$TEST_ROOT/linked-home" \
  "$DOTFILES_DIR/scripts/materialize-agent-configs.sh" "$DOTFILES_DIR" "$(command -v jq)"
[[ ! -L "$TEST_ROOT/linked-home/.claude/settings.json" ]]
assert_json_value "$TEST_ROOT/linked-home/.claude/settings.json" '.model' 'linked-model'
assert_json_value "$TEST_ROOT/linked-home/.claude/settings.json" '.theme' 'auto'

printf '%s\n' 'agent config materialization tests passed'
