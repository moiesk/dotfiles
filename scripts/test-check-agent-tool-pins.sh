#!/usr/bin/env bash
# Focused drift tests for scripts/check-agent-tool-pins.sh.
# Synthetic versions are derived from the live pins so routine bumps cannot
# make these fixtures stale.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CHECKER="$DOTFILES_DIR/scripts/check-agent-tool-pins.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

FIXTURE_NAME="$(basename "${BASH_SOURCE[0]}")"

fixture_error() {
  printf 'error: the fixture in scripts/%s is degenerate: %s\n' "$FIXTURE_NAME" "$1" >&2
  printf '%s\n' \
    'the scenario under test was never constructed, so this says nothing about' \
    'scripts/check-agent-tool-pins.sh; repair the fixture instead' >&2
  exit 1
}

checker_error() {
  printf 'error: scripts/check-agent-tool-pins.sh regressed: %s\n' "$1" >&2
  exit 1
}

copy_pin_files() {
  rm -rf "$tmp_dir/repo"
  mkdir -p "$tmp_dir/repo/agent-tools" "$tmp_dir/repo/scripts"
  cp "$DOTFILES_DIR/flake.nix" "$DOTFILES_DIR/flake.lock" \
    "$DOTFILES_DIR/TRUST.md" "$tmp_dir/repo/"
  cp "$DOTFILES_DIR/agent-tools/package.json" \
    "$DOTFILES_DIR/agent-tools/package-lock.json" \
    "$tmp_dir/repo/agent-tools/"
  cp "$DOTFILES_DIR/scripts/agent-tool-pins.tsv" "$tmp_dir/repo/scripts/"
}

replace_file_text() {
  local file="$1" old="$2" new="$3" count escaped_old escaped_new
  count="$(grep -F -o -- "$old" "$file" | grep -c '' || true)"
  [[ "$count" == "1" ]] ||
    fixture_error "expected exactly one occurrence of '$old' in $file, found $count"
  escaped_old="$(printf '%s' "$old" | sed 's#[][\\.*^$/|]#\\&#g')"
  escaped_new="$(printf '%s' "$new" | sed 's#[\\&|]#\\&#g')"
  sed "s|$escaped_old|$escaped_new|" "$file" >"$file.new"
  mv "$file.new" "$file"
}

replace_json() {
  local file="$1" filter="$2"
  shift 2
  jq "$@" "$filter" "$file" >"$file.new"
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

tested_tools=0
while IFS=$'\t' read -r flake_input tool tag_prefix extra; do
  [[ -z "$flake_input" || "$flake_input" == \#* ]] && continue
  [[ -n "$tool" && -n "$tag_prefix" && -z "${extra:-}" ]] ||
    fixture_error "invalid inventory record for $flake_input"
  tested_tools=$((tested_tools + 1))
  pinned="$(jq -er --arg tool "$tool" '.dependencies[$tool]' \
    "$DOTFILES_DIR/agent-tools/package.json")"
  [[ "$pinned" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] ||
    fixture_error "$tool pin ($pinned) is not a plain major.minor.patch version"
  bumped="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"
  pinned_ref="${tag_prefix}${pinned}"
  bumped_ref="${tag_prefix}${bumped}"

  # A coordinated npm-surface move must still fail until the flake surface moves.
  copy_pin_files
  replace_json "$tmp_dir/repo/agent-tools/package.json" \
    '.dependencies[$tool] = $bumped' --arg tool "$tool" --arg bumped "$bumped"
  replace_json "$tmp_dir/repo/agent-tools/package-lock.json" \
    '.packages[""].dependencies[$tool] = $bumped | .packages[$path].version = $bumped' \
    --arg tool "$tool" --arg path "node_modules/$tool" --arg bumped "$bumped"
  expect_failure "error: $tool flake.nix ref $pinned_ref does not match npm version $bumped"

  # A coordinated flake-surface move must still fail until the npm surface moves.
  copy_pin_files
  replace_file_text "$tmp_dir/repo/flake.nix" "/$pinned_ref\";" "/$bumped_ref\";"
  replace_json "$tmp_dir/repo/flake.lock" '.nodes[$tool].original.ref = $ref' \
    --arg tool "$flake_input" --arg ref "$bumped_ref"
  expect_failure "error: $tool flake.nix ref $bumped_ref does not match npm version $pinned"

  # One-sided lockfile edits get lock-specific diagnostics.
  copy_pin_files
  replace_json "$tmp_dir/repo/agent-tools/package-lock.json" \
    '.packages[""].dependencies[$tool] = $bumped' \
    --arg tool "$tool" --arg bumped "$bumped"
  expect_failure "error: $tool npm manifest version $pinned does not match package-lock root version $bumped"

  copy_pin_files
  replace_json "$tmp_dir/repo/agent-tools/package-lock.json" \
    '.packages[$path].version = $bumped' \
    --arg path "node_modules/$tool" --arg bumped "$bumped"
  expect_failure "error: $tool npm manifest version $pinned does not match package-lock installed version $bumped"

  copy_pin_files
  replace_json "$tmp_dir/repo/flake.lock" '.nodes[$tool].original.ref = $ref' \
    --arg tool "$flake_input" --arg ref "$bumped_ref"
  expect_failure "error: $tool flake.nix ref $pinned_ref does not match flake.lock ref $bumped_ref"

  # TRUST.md is a pin surface too: deliberately drifting its release tag must fail.
  copy_pin_files
  replace_file_text "$tmp_dir/repo/TRUST.md" "$pinned_ref" "$bumped_ref"
  expect_failure "error: TRUST.md row for $tool does not document exactly one current pin $pinned_ref"
done <"$DOTFILES_DIR/scripts/agent-tool-pins.tsv"

[[ "$tested_tools" -gt 0 ]] || fixture_error 'the shared agent tool inventory is empty'

# A newly added npm-backed AXI dependency cannot silently miss checker/test coverage.
copy_pin_files
replace_json "$tmp_dir/repo/agent-tools/package.json" \
  '.dependencies["unlisted-axi"] = "1.2.3"'
replace_json "$tmp_dir/repo/agent-tools/package-lock.json" \
  '.packages[""].dependencies["unlisted-axi"] = "1.2.3"
  | .packages["node_modules/unlisted-axi"] = {"version": "1.2.3"}'
expect_failure 'error: npm-backed AXI dependency unlisted-axi is missing from scripts/agent-tool-pins.tsv'

printf '%s\n' 'agent tool pin checks passed'
