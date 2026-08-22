#!/usr/bin/env bash
# Focused drift tests for scripts/check-opencode-trust.sh.
# Synthetic versions are derived from the live pin so routine bumps cannot make
# these fixtures stale.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CHECKER="$DOTFILES_DIR/scripts/check-opencode-trust.sh"
CONFIG_DIR="home/.config/opencode"
WORKFLOW_PATH=".github/workflows/agent-tool-pins.yml"
PACKAGE="@opencode-ai/plugin"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

FIXTURE_NAME="$(basename "${BASH_SOURCE[0]}")"

fixture_error() {
  printf 'error: the fixture in scripts/%s is degenerate: %s\n' "$FIXTURE_NAME" "$1" >&2
  printf '%s\n' \
    'the scenario under test was never constructed, so this says nothing about' \
    'scripts/check-opencode-trust.sh; repair the fixture instead' >&2
  exit 1
}

checker_error() {
  printf 'error: scripts/check-opencode-trust.sh regressed: %s\n' "$1" >&2
  exit 1
}

copy_trust_files() {
  rm -rf "$tmp_dir/repo"
  mkdir -p "$tmp_dir/repo/$CONFIG_DIR" "$tmp_dir/repo/$(dirname "$WORKFLOW_PATH")"
  cp "$DOTFILES_DIR/TRUST.md" "$tmp_dir/repo/"
  cp "$DOTFILES_DIR/$WORKFLOW_PATH" "$tmp_dir/repo/$WORKFLOW_PATH"
  cp "$DOTFILES_DIR/$CONFIG_DIR/package.json" \
    "$DOTFILES_DIR/$CONFIG_DIR/package-lock.json" \
    "$DOTFILES_DIR/$CONFIG_DIR/.npmrc" \
    "$tmp_dir/repo/$CONFIG_DIR/"
  git -C "$tmp_dir/repo" init --quiet
  git -C "$tmp_dir/repo" add --all
}

replace_file_text() {
  local file="$1" old="$2" new="$3" count escaped_old escaped_new
  count="$(grep -F -o -- "$old" "$file" | grep -c '' || true)"
  [[ "$count" -ge 1 ]] ||
    fixture_error "expected at least one occurrence of '$old' in $file"
  escaped_old="$(printf '%s' "$old" | sed 's#[][\\.*^$/|]#\\&#g')"
  escaped_new="$(printf '%s' "$new" | sed 's#[\\&|]#\\&#g')"
  sed "s|$escaped_old|$escaped_new|g" "$file" >"$file.new"
  mv "$file.new" "$file"
}

expect_failure() {
  local expected="$1" output
  if output="$(DOTFILES_DIR="$tmp_dir/repo" "$CHECKER" 2>&1)"; then
    printf '%s\n' "$output" >&2
    checker_error "the checker accepted injected drift; expected: $expected"
  fi
  if ! grep -Fq "$expected" <<<"$output"; then
    printf '%s\n' "$output" >&2
    checker_error "the checker did not report the drift clearly; expected: $expected"
  fi
}

pinned="$(jq -er --arg package "$PACKAGE" '.dependencies[$package]' \
  "$DOTFILES_DIR/$CONFIG_DIR/package.json")"
[[ "$pinned" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] ||
  fixture_error "$PACKAGE pin ($pinned) is not a plain major.minor.patch version"
bumped="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"

grep -q '^## Tier C' "$DOTFILES_DIR/TRUST.md" ||
  fixture_error 'TRUST.md no longer has a Tier C section to classify OpenCode under'

# The unmodified checkout must pass, or every failure below proves nothing.
copy_trust_files
if ! DOTFILES_DIR="$tmp_dir/repo" "$CHECKER" >/dev/null 2>&1; then
  DOTFILES_DIR="$tmp_dir/repo" "$CHECKER" || true
  fixture_error 'the pristine copy of the repository already fails the checker'
fi

# A merged manifest bump must fail until TRUST.md documents the new pin.
copy_trust_files
jq --arg package "$PACKAGE" --arg bumped "$bumped" \
  '.dependencies[$package] = $bumped' \
  "$tmp_dir/repo/$CONFIG_DIR/package.json" >"$tmp_dir/manifest.json"
mv "$tmp_dir/manifest.json" "$tmp_dir/repo/$CONFIG_DIR/package.json"
expect_failure "error: TRUST.md row for $PACKAGE does not document exactly one current pin $PACKAGE@$bumped"

# Documenting the new pin without refreshing the cited release evidence must fail.
copy_trust_files
jq --arg package "$PACKAGE" --arg bumped "$bumped" \
  '.dependencies[$package] = $bumped' \
  "$tmp_dir/repo/$CONFIG_DIR/package.json" >"$tmp_dir/manifest.json"
mv "$tmp_dir/manifest.json" "$tmp_dir/repo/$CONFIG_DIR/package.json"
replace_file_text "$tmp_dir/repo/TRUST.md" "$PACKAGE@$pinned" "$PACKAGE@$bumped"
expect_failure "error: TRUST.md cites anomalyco/opencode evidence at v$pinned but $CONFIG_DIR/package.json installs $bumped"

# Dropping the row entirely must fail rather than silently un-inventorying it.
copy_trust_files
grep -v -F -- "\`$PACKAGE\`" "$tmp_dir/repo/TRUST.md" >"$tmp_dir/trust.md"
mv "$tmp_dir/trust.md" "$tmp_dir/repo/TRUST.md"
expect_failure "error: TRUST.md must contain exactly one inventory row for $PACKAGE (found 0)"

# Tracked runtime plugin code invalidates the Tier C classification.
for runtime_file in plugin/notify.ts tool/deploy.js; do
  copy_trust_files
  mkdir -p "$tmp_dir/repo/$CONFIG_DIR/$(dirname "$runtime_file")"
  printf '%s\n' 'export const plugin = async ({ $ }) => ({})' \
    >"$tmp_dir/repo/$CONFIG_DIR/$runtime_file"
  git -C "$tmp_dir/repo" add --all
  git -C "$tmp_dir/repo" ls-files --error-unmatch -- "$CONFIG_DIR/$runtime_file" >/dev/null ||
    fixture_error "failed to track $runtime_file, so the escalation was never staged"
  expect_failure "$CONFIG_DIR/$runtime_file adds runtime OpenCode plugin/tool code"
done

# An untracked local scratch file is not an inventory escalation.
copy_trust_files
printf '%s\n' 'scratch' >"$tmp_dir/repo/$CONFIG_DIR/scratch.ts"
if ! DOTFILES_DIR="$tmp_dir/repo" "$CHECKER" >/dev/null 2>&1; then
  checker_error 'an untracked scratch file was treated as a committed capability escalation'
fi

# A permalink that stops at the ref must be version-checked too, not skipped
# because it has no trailing path segment.
for stale_link in \
  "https://github.com/anomalyco/opencode/tree/v$bumped" \
  "https://github.com/anomalyco/opencode/releases/tag/v$bumped"; do
  copy_trust_files
  printf '\nStale evidence: [upstream](%s).\n' "$stale_link" >>"$tmp_dir/repo/TRUST.md"
  expect_failure "error: TRUST.md cites anomalyco/opencode evidence at v$bumped but $CONFIG_DIR/package.json installs $pinned"
done

# A well-formed permalink at the installed version must still pass, so the
# hardened pattern is not simply rejecting every bare-ref link.
copy_trust_files
printf '\nCurrent evidence: [upstream](https://github.com/anomalyco/opencode/tree/v%s).\n' \
  "$pinned" >>"$tmp_dir/repo/TRUST.md"
if ! DOTFILES_DIR="$tmp_dir/repo" "$CHECKER" >/dev/null 2>&1; then
  checker_error 'a bare-ref permalink at the installed version was rejected'
fi

# The checker must fail closed when it stops running in pull-request CI.
copy_trust_files
grep -v -F -- 'run: ./scripts/check-opencode-trust.sh' \
  "$tmp_dir/repo/$WORKFLOW_PATH" >"$tmp_dir/workflow.yml"
mv "$tmp_dir/workflow.yml" "$tmp_dir/repo/$WORKFLOW_PATH"
expect_failure "needs 1 occurrence(s) of run: ./scripts/check-opencode-trust.sh (found 0)"

# Losing a path filter silently stops CI from firing on the drift it guards.
for filter_path in "$CONFIG_DIR/package.json" "scripts/check-opencode-trust.sh" "TRUST.md"; do
  copy_trust_files
  filter_line="      - \"$filter_path\""
  occurrences="$(grep -F -o -- "$filter_line" "$tmp_dir/repo/$WORKFLOW_PATH" | grep -c '' || true)"
  [[ "$occurrences" == "2" ]] ||
    fixture_error "expected $filter_path in both trigger blocks, found $occurrences"
  awk -v line="$filter_line" 'BEGIN { dropped = 0 }
    $0 == line && dropped == 0 { dropped = 1; next }
    { print }' "$tmp_dir/repo/$WORKFLOW_PATH" >"$tmp_dir/workflow.yml"
  mv "$tmp_dir/workflow.yml" "$tmp_dir/repo/$WORKFLOW_PATH"
  expect_failure "needs 2 occurrence(s) of - \"$filter_path\" (found 1)"
done

printf '%s\n' 'OpenCode trust checker tests passed'
