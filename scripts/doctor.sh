#!/usr/bin/env bash
# Verify the important outcomes without changing the machine.
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FAILURES=0

pass() { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m✗\033[0m %s\n' "$*"; FAILURES=$((FAILURES + 1)); }

for command_name in nix brew git gh codex claude pi opencode ghostty herdr nvim starship fzf mise uv bun gh-axi chrome-devtools-axi lavish-axi treehouse no-mistakes; do
  if command -v "$command_name" >/dev/null 2>&1; then
    pass "$command_name is available"
  else
    fail "$command_name is missing"
  fi
done

for agent_helper in gh-axi chrome-devtools-axi lavish-axi; do
  if "$agent_helper" --help >/dev/null 2>&1; then
    pass "$agent_helper runs successfully"
  else
    fail "$agent_helper is installed but cannot run"
  fi
done

if [[ -d "$HOME/firstmate/.git" ]] &&
  git -C "$HOME/firstmate" remote get-url origin 2>/dev/null | rg -q '(^|[:/])kunchenguid/firstmate(?:\.git)?$'; then
  pass "Firstmate agent distro is installed"
else
  fail "Firstmate agent distro is missing or has an unexpected origin"
fi

for skill_name in setup-matt-pocock-skills lavish; do
  skill_path="$HOME/.agents/skills/$skill_name/SKILL.md"
  if [[ -r "$skill_path" ]]; then
    pass "$skill_name skill is available"
  else
    fail "$skill_name skill is missing"
  fi
done

if [[ "$(mise exec -- node --version 2>/dev/null)" == "v24.6.0" ]]; then
  pass "mise provides Node 24.6.0"
else
  fail "mise does not provide Node 24.6.0"
fi

if mise exec -- ruby --version 2>/dev/null | rg -q '^ruby 3\.4\.5'; then
  pass "mise provides Ruby 3.4.5"
else
  fail "mise does not provide Ruby 3.4.5"
fi

if [[ -r /opt/homebrew/share/zsh/site-functions/_brew ]]; then
  pass "Homebrew zsh completion is readable"
else
  fail "Homebrew zsh completion is missing or points to a missing target"
fi

for target in \
  "$HOME/.codex/AGENTS.md" \
  "$HOME/.claude/CLAUDE.md" \
  "$HOME/.pi/agent/AGENTS.md" \
  "$HOME/.config/opencode/AGENTS.md"; do
  if [[ -L "$target" ]] && cmp -s "$target" "$DOTFILES_DIR/AGENTS.md"; then
    pass "$target uses the canonical AGENTS.md"
  else
    fail "$target is not linked to the canonical AGENTS.md"
  fi
done

check_default() {
  local label="$1" expected="$2"
  shift 2
  local actual
  actual="$(defaults read "$@" 2>/dev/null || true)"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label = $expected"
  else
    fail "$label expected $expected, got ${actual:-<unset>}"
  fi
}

check_default "Dock autohide" "1" com.apple.dock autohide
check_default "Automatic appearance" "1" -g AppleInterfaceStyleSwitchesAutomatically
check_default "Finder tab bar" "1" com.apple.finder ShowTabView
check_default "Finder prefers tabs" "always" com.apple.finder AppleWindowTabbingMode

if [[ "$FAILURES" -gt 0 ]]; then
  printf '\n%d check(s) failed.\n' "$FAILURES" >&2
  exit 1
fi

printf '\nAll checks passed.\n'
