#!/usr/bin/env bash
# Deterministic policy tests for Firstmate dependency-floor exceptions.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CHECKER="$DOTFILES_DIR/scripts/check-firstmate-floor-exceptions.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  printf 'error: Firstmate floor exception test failed: %s\n' "$1" >&2
  exit 1
}

fixture_error() {
  printf 'error: the fixture in scripts/%s is degenerate: %s\n' \
    "$(basename "${BASH_SOURCE[0]}")" "$1" >&2
  exit 1
}

live_pin="$(jq -er '.dependencies["quota-axi"]' \
  "$DOTFILES_DIR/agent-tools/package.json")" ||
  fixture_error 'the live quota-axi pin is missing'
[[ "$live_pin" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] ||
  fixture_error "the live quota-axi pin is not plain semver: $live_pin"
((BASH_REMATCH[3] >= 2)) ||
  fixture_error "the live quota-axi patch $live_pin cannot yield two lower fixture versions"
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"
previous_previous="$major.$minor.$((patch - 2))"
previous="$major.$minor.$((patch - 1))"
adopted="$live_pin"
broader="$major.$minor.$((patch + 1))"
latest="$major.$minor.$((patch + 2))"

commit='2222222222222222222222222222222222222222'
now_epoch=1786752000 # 2026-08-15T00:00:00Z
fresh_at='2026-08-13T06:34:14Z'
fresh_release_at="$fresh_at"
old_at='2026-07-01T00:00:00Z'

mkdir -p "$tmp_dir/repo/agent-tools" "$tmp_dir/bin"
jq -n --arg pin "$previous" '{dependencies: {"quota-axi": $pin}}' \
  >"$tmp_dir/repo/agent-tools/package.json"
awk -F '\t' '$1 ~ /^#/ || $1 == "quota-axi"' \
  "$DOTFILES_DIR/scripts/firstmate-tool-floors.tsv" >"$tmp_dir/repo/floors.tsv"
git -C "$tmp_dir/repo" init -q
git -C "$tmp_dir/repo" config user.name 'Fixture Test'
git -C "$tmp_dir/repo" config user.email 'fixture@example.invalid'
git -C "$tmp_dir/repo" add agent-tools/package.json floors.tsv
git -C "$tmp_dir/repo" commit -qm 'historical pin fixture'
jq -n --arg pin "$adopted" '{dependencies: {"quota-axi": $pin}}' \
  >"$tmp_dir/repo/agent-tools/package.json"

cat >"$tmp_dir/bin/gh-axi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == *"/repos/kunchenguid/firstmate/contents/bin/fm-quota-axi-lib.sh?ref=$FIXTURE_COMMIT"* ]] || exit 1
printf 'api_response:\n  body: %s\n  truncated: false\n' "$FIXTURE_REQUIRED"
EOF

cat >"$tmp_dir/bin/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
jq -n \
  --arg previous "$FIXTURE_PREVIOUS" \
  --arg adopted "$FIXTURE_ADOPTED" \
  --arg broader "$FIXTURE_BROADER" \
  --arg latest "$FIXTURE_LATEST" \
  --arg fresh_at "$FIXTURE_FRESH_AT" \
  --arg old_at "$FIXTURE_OLD_AT" \
  '{
    "dist-tags": {latest: $latest},
    versions: [$previous, $adopted, $broader, $latest],
    time: {
      ($previous): $old_at,
      ($adopted): $fresh_at,
      ($broader): $fresh_at,
      ($latest): $fresh_at
    }
  }'
EOF
chmod +x "$tmp_dir/bin/gh-axi" "$tmp_dir/bin/npm"

write_exception() {
  jq -n \
    --arg dependency "${1:-quota-axi}" \
    --arg adopted "${2:-$adopted}" \
    --arg required "${3:-$adopted}" \
    --arg commit "${4:-$commit}" \
    --arg previous "${5:-$previous}" \
    '{
      schema_version: 1,
      exceptions: [{
        dependency: $dependency,
        previous_version: $previous,
        adopted_version: $adopted,
        required_version: $required,
        firstmate_repository: "kunchenguid/firstmate",
        firstmate_commit: $commit
      }]
    }' >"$tmp_dir/repo/exceptions.json"
}

run_checker() {
  DOTFILES_DIR="$tmp_dir/repo" \
    DOTFILES_HISTORY_DIR="$tmp_dir/repo" \
    FIRSTMATE_FLOOR_REGISTRY="$tmp_dir/repo/floors.tsv" \
    FIRSTMATE_FLOOR_EXCEPTIONS_FILE="$tmp_dir/repo/exceptions.json" \
    GH_AXI_BIN="$tmp_dir/bin/gh-axi" \
    NPM_BIN="$tmp_dir/bin/npm" \
    TOOL_UPDATE_NOW_EPOCH="$now_epoch" \
    TOOL_UPDATE_COOLDOWN_DAYS=7 \
    FIXTURE_COMMIT="$commit" \
    FIXTURE_REQUIRED="$adopted" \
    FIXTURE_PREVIOUS="$previous" \
    FIXTURE_ADOPTED="$adopted" \
    FIXTURE_BROADER="$broader" \
    FIXTURE_LATEST="$latest" \
    FIXTURE_FRESH_AT="$fresh_at" \
    FIXTURE_OLD_AT="$old_at" \
    "$CHECKER" "$@"
}

expect_failure() {
  local expected="$1"
  if run_checker >"$tmp_dir/output" 2>&1; then
    fail "expected rejection containing: $expected"
  fi
  grep -Fq "$expected" "$tmp_dir/output" || {
    cat "$tmp_dir/output" >&2
    fail "rejection did not contain: $expected"
  }
}

write_exception
run_checker >/dev/null || fail 'valid exact-commit floor exception was rejected'

write_exception quota-axi "$broader" "$adopted"
jq --arg pin "$broader" '.dependencies["quota-axi"] = $pin' "$tmp_dir/repo/agent-tools/package.json" \
  >"$tmp_dir/repo/agent-tools/package.json.next"
mv "$tmp_dir/repo/agent-tools/package.json.next" "$tmp_dir/repo/agent-tools/package.json"
expect_failure "is broader than the lowest released version $adopted"

write_exception treehouse "$adopted" "$adopted"
expect_failure 'does not name a supported Firstmate dependency floor'

write_exception quota-axi "$previous" "$adopted"
jq --arg pin "$previous" '.dependencies["quota-axi"] = $pin' "$tmp_dir/repo/agent-tools/package.json" \
  >"$tmp_dir/repo/agent-tools/package.json.next"
mv "$tmp_dir/repo/agent-tools/package.json.next" "$tmp_dir/repo/agent-tools/package.json"
expect_failure "does not satisfy required version $adopted"

write_exception quota-axi "$adopted" "$previous" "$commit" "$previous_previous"
jq --arg pin "$adopted" '.dependencies["quota-axi"] = $pin' "$tmp_dir/repo/agent-tools/package.json" \
  >"$tmp_dir/repo/agent-tools/package.json.next"
mv "$tmp_dir/repo/agent-tools/package.json.next" "$tmp_dir/repo/agent-tools/package.json"
expect_failure "declares quota-axi floor $adopted, not recorded required version $previous"

write_exception quota-axi "$adopted" "$adopted" 1111111111111111111111111111111111111111
expect_failure 'could not read Firstmate floor evidence'

write_exception quota-axi "$adopted" "$adopted" "$commit" "$adopted"
expect_failure "is unrelated because previous pin $adopted already satisfied required version $adopted"

write_exception quota-axi "$adopted" "$adopted" "$commit" "$previous_previous"
expect_failure "previous version $previous_previous does not match historical pin $previous"

write_exception
fresh_at="$old_at"
expect_failure "exception is stale because adopted version $adopted has completed the 7-day cooldown"
grep -Fq -- '--retire-expired' "$tmp_dir/output" ||
  fail 'stale rejection did not name the retirement command'
fresh_at="$fresh_release_at"

# An exception still inside the cooldown is kept, and the run warns before the
# retirement deadline instead of failing without notice later.
write_exception
run_checker >"$tmp_dir/output" 2>&1 || fail 'valid exception was rejected before its retirement'
grep -Fq 'retire in ' "$tmp_dir/output" ||
  fail 'valid exception did not report its remaining retirement window'
run_checker --retire-expired >"$tmp_dir/output" 2>&1 ||
  fail 'retirement failed while the exception was still inside cooldown'
grep -Fq 'no Firstmate floor exception has completed the 7-day cooldown' "$tmp_dir/output" || {
  cat "$tmp_dir/output" >&2
  fail 'retirement did not report that nothing was expired'
}
jq -e '(.exceptions | length) == 1' "$tmp_dir/repo/exceptions.json" >/dev/null ||
  fail 'retirement removed an exception that was still inside cooldown'

fresh_at="$old_at"
run_checker --retire-expired >"$tmp_dir/output" 2>&1 || {
  cat "$tmp_dir/output" >&2
  fail 'retirement of an expired exception failed'
}
grep -Fq 'retired Firstmate floor exception: quota-axi' "$tmp_dir/output" ||
  fail 'retirement did not report the removed exception'
jq -e '.schema_version == 1 and (.exceptions | length) == 0' \
  "$tmp_dir/repo/exceptions.json" >/dev/null ||
  fail 'retirement did not delete the expired exception record'
run_checker >/dev/null 2>&1 || fail 'validation still failed after retiring expired evidence'
fresh_at="$fresh_release_at"

jq -n --arg pin "$previous" '{dependencies: {"quota-axi": $pin}}' \
  >"$tmp_dir/repo/agent-tools/package.json"
if DOTFILES_DIR="$tmp_dir/repo" \
  FIRSTMATE_FLOOR_REGISTRY="$tmp_dir/repo/floors.tsv" \
  GH_AXI_BIN="$tmp_dir/bin/gh-axi" \
  FIXTURE_COMMIT="$commit" \
  FIXTURE_REQUIRED="$adopted" \
  "$CHECKER" --candidate "$commit" >"$tmp_dir/output" 2>&1; then
  fail 'candidate preflight accepted an unmet quota-axi floor'
fi
grep -Fq "unmet: quota-axi pin $previous is below Firstmate floor $adopted" "$tmp_dir/output" || {
  cat "$tmp_dir/output" >&2
  fail 'candidate preflight did not report the unmet floor'
}

# GitHub-release dependencies also select the lowest published version above a
# floor that is not itself a release; Firstmate tags are never consulted.
github_ref="$(jq -er '.nodes["no-mistakes"].original.ref' "$DOTFILES_DIR/flake.lock")" ||
  fixture_error 'the live no-mistakes flake ref is missing'
[[ "$github_ref" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] ||
  fixture_error "the live no-mistakes ref is not a v-prefixed semver: $github_ref"
github_major="${BASH_REMATCH[1]}"
github_minor="${BASH_REMATCH[2]}"
github_patch="${BASH_REMATCH[3]}"
# Derive the synthetic gap above the live ref: counting up cannot underflow, so
# the scenario survives any released patch level, including x.y.0 and x.y.1.
github_previous="$github_major.$github_minor.$github_patch"
github_required="$github_major.$github_minor.$((github_patch + 1))"
github_adopted="$github_major.$github_minor.$((github_patch + 2))"
github_newer="$github_major.$github_minor.$((github_patch + 3))"
github_repo="$tmp_dir/github-repo"
mkdir -p "$github_repo/scripts"
awk -F '\t' '$1 ~ /^#/ || $1 == "no-mistakes"' \
  "$DOTFILES_DIR/scripts/firstmate-tool-floors.tsv" >"$github_repo/floors.tsv"
jq -n --arg ref "v$github_previous" \
  '{nodes: {"no-mistakes": {original: {ref: $ref}}}}' >"$github_repo/flake.lock"
git -C "$github_repo" init -q
git -C "$github_repo" config user.name 'Fixture Test'
git -C "$github_repo" config user.email 'fixture@example.invalid'
git -C "$github_repo" add floors.tsv flake.lock
git -C "$github_repo" commit -qm 'historical GitHub pin fixture'
jq -n --arg ref "v$github_adopted" \
  '{nodes: {"no-mistakes": {original: {ref: $ref}}}}' >"$github_repo/flake.lock"
jq -n \
  --arg previous "$github_previous" \
  --arg adopted "$github_adopted" \
  --arg required "$github_required" \
  --arg commit "$commit" \
  '{schema_version: 1, exceptions: [{
    dependency: "no-mistakes",
    previous_version: $previous,
    adopted_version: $adopted,
    required_version: $required,
    firstmate_repository: "kunchenguid/firstmate",
    firstmate_commit: $commit
  }]}' >"$github_repo/exceptions.json"
cat >"$tmp_dir/bin/gh-axi-github" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"/repos/kunchenguid/firstmate/contents/bin/fm-bootstrap.sh?ref=$FIXTURE_COMMIT"*)
    printf 'api_response:\n  body: %s\n  truncated: false\n' "$FIXTURE_GITHUB_REQUIRED"
    ;;
  *"/repos/kunchenguid/no-mistakes/releases?per_page=100"*)
    body="$(printf 'v%s\nv%s\nv%s\n' \
      "$FIXTURE_GITHUB_PREVIOUS" "$FIXTURE_GITHUB_ADOPTED" "$FIXTURE_GITHUB_NEWER" | jq -Rs .)"
    printf 'api_response:\n  body: %s\n  truncated: false\n' "$body"
    ;;
  *"/repos/kunchenguid/no-mistakes/releases/tags/v$FIXTURE_GITHUB_ADOPTED"*)
    printf 'tag_name: v%s\npublished_at: "%s"\n' \
      "$FIXTURE_GITHUB_ADOPTED" "$FIXTURE_FRESH_AT"
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp_dir/bin/gh-axi-github"
DOTFILES_DIR="$github_repo" \
  FIRSTMATE_FLOOR_REGISTRY="$github_repo/floors.tsv" \
  FIRSTMATE_FLOOR_EXCEPTIONS_FILE="$github_repo/exceptions.json" \
  GH_AXI_BIN="$tmp_dir/bin/gh-axi-github" \
  TOOL_UPDATE_NOW_EPOCH="$now_epoch" \
  TOOL_UPDATE_COOLDOWN_DAYS=7 \
  FIXTURE_COMMIT="$commit" \
  FIXTURE_GITHUB_PREVIOUS="$github_previous" \
  FIXTURE_GITHUB_REQUIRED="$github_required" \
  FIXTURE_GITHUB_ADOPTED="$github_adopted" \
  FIXTURE_GITHUB_NEWER="$github_newer" \
  FIXTURE_FRESH_AT="$fresh_release_at" \
  "$CHECKER" >/dev/null ||
  fail 'GitHub release gap did not select the lowest satisfying published version'

printf '%s\n' 'Firstmate floor exception checks passed'
