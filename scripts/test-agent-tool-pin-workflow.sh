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
  'scripts/check-firstmate-floor-exceptions.sh' \
  'scripts/firstmate-tool-floors.tsv' \
  'security/firstmate-floor-exceptions.json' \
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

# The workflow installs nothing beyond actions/checkout, so every script it runs
# may only use tools preinstalled on the runner; ripgrep is not one of them. The
# scan covers every step line, so a `- name:` step with a continuation `run:`
# cannot smuggle an install past the uses/run counts.
steps_block="$(awk '
  /^    steps:$/ { in_steps = 1; next }
  in_steps && /^ {0,3}[^ ]/ { in_steps = 0 }
  in_steps { print }
' "$WORKFLOW")"
[[ -n "$steps_block" ]] || fail 'workflow must declare a steps block'
step_count="$(printf '%s\n' "$steps_block" | rg -c '^      - ' || true)"
[[ "$(printf '%s\n' "$steps_block" | rg -c '^      - uses: actions/checkout@' || true)" == "1" ]] ||
  fail 'workflow must use exactly one action, actions/checkout, and install no tools'
[[ -z "$(printf '%s\n' "$steps_block" | rg '^        ' || true)" ]] ||
  fail 'workflow steps must be single-line uses/run steps, with no continuation keys'
run_steps="$(printf '%s\n' "$steps_block" | rg -o -r '$1' '^      - run: (.+)$' || true)"
[[ -n "$run_steps" ]] || fail 'workflow must run at least one repository checker'
run_count="$(printf '%s\n' "$run_steps" | rg -c '.' || true)"
[[ "$step_count" == "$((run_count + 1))" ]] ||
  fail "every workflow step must be actions/checkout or a repository checker run step (found $step_count steps, $run_count checkers)"
while IFS= read -r run_step; do
  [[ "$run_step" == ./scripts/*.sh ]] ||
    fail "workflow steps must be repository checker scripts, not inline commands: $run_step"
  checker="$DOTFILES_DIR/${run_step#./}"
  [[ -x "$checker" ]] || fail "workflow runs a missing or non-executable script: $run_step"
  if rg -qw 'rg' "$checker"; then
    fail "$run_step must not depend on ripgrep, which is absent from the CI runner"
  fi
done <<<"$run_steps"

printf '%s\n' 'agent tool pin workflow checks passed'
