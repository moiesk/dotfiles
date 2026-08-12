#!/usr/bin/env bash
# Focused contract test for the AXI pin-alignment GitHub Actions workflow.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORKFLOW="$DOTFILES_DIR/.github/workflows/agent-tool-pins.yml"

fail() {
  printf 'error: agent tool pin workflow regressed: %s\n' "$1" >&2
  exit 1
}

[[ -f "$WORKFLOW" ]] || fail 'workflow file is missing'
[[ "$(rg -c '^  pull_request:$' "$WORKFLOW" || true)" == "1" ]] ||
  fail 'pull_request trigger must appear exactly once'
[[ "$(rg -c '^  push:$' "$WORKFLOW" || true)" == "1" ]] ||
  fail 'push trigger must appear exactly once'
[[ "$(rg -c '^      - main$' "$WORKFLOW" || true)" == "1" ]] ||
  fail 'push must remain limited to main'

for path in \
  '.github/workflows/agent-tool-pins.yml' \
  'agent-tools/package.json' \
  'agent-tools/package-lock.json' \
  'flake.lock' \
  'flake.nix' \
  'scripts/agent-tool-pins.tsv' \
  'scripts/check-agent-tool-pins.sh' \
  'scripts/test-agent-tool-pin-workflow.sh' \
  'scripts/test-check-agent-tool-pins.sh' \
  'scripts/test-update-agent-tool-pin.sh' \
  'scripts/update-agent-tool-pin.sh' \
  'TRUST.md'; do
  count="$(rg -Fc -- "      - \"$path\"" "$WORKFLOW" || true)"
  [[ "$count" == "2" ]] ||
    fail "$path must be included once in both pull_request and push paths (found $count)"
done

[[ "$(rg -c '^permissions:$' "$WORKFLOW" || true)" == "1" ]] ||
  fail 'workflow must declare top-level permissions'
[[ "$(rg -c '^  contents: read$' "$WORKFLOW" || true)" == "1" ]] ||
  fail 'workflow permissions must remain read-only'
[[ "$(rg -Fc -- '      - run: ./scripts/check-agent-tool-pins.sh' "$WORKFLOW" || true)" == "1" ]] ||
  fail 'workflow must invoke the repository checker exactly once'

printf '%s\n' 'agent tool pin workflow checks passed'
