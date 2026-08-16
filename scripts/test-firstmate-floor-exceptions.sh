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

commit='f1a4af426d7199c1781bc91ccd143b8e1f732d10'
now_epoch=1786752000 # 2026-08-15T00:00:00Z
fresh_at='2026-08-13T06:34:14Z'
old_at='2026-07-01T00:00:00Z'

mkdir -p "$tmp_dir/repo/agent-tools" "$tmp_dir/bin"
printf '{"dependencies":{"quota-axi":"0.1.25"}}\n' >"$tmp_dir/repo/agent-tools/package.json"
awk -F '\t' '$1 ~ /^#/ || $1 == "quota-axi"' \
  "$DOTFILES_DIR/scripts/firstmate-tool-floors.tsv" >"$tmp_dir/repo/floors.tsv"

cat >"$tmp_dir/bin/gh-axi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == *"/repos/kunchenguid/firstmate/contents/bin/fm-quota-axi-lib.sh?ref=$FIXTURE_COMMIT"* ]] || exit 1
printf 'api_response:\n  body: 0.1.25\n  truncated: false\n'
EOF

cat >"$tmp_dir/bin/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
jq -n \
  --arg fresh_at "$FIXTURE_FRESH_AT" \
  --arg old_at "$FIXTURE_OLD_AT" \
  '{
    "dist-tags": {latest: "0.1.28"},
    versions: ["0.1.24", "0.1.25", "0.1.26", "0.1.28"],
    time: {
      "0.1.24": $old_at,
      "0.1.25": $fresh_at,
      "0.1.26": $fresh_at,
      "0.1.28": $fresh_at
    }
  }'
EOF
chmod +x "$tmp_dir/bin/gh-axi" "$tmp_dir/bin/npm"

write_exception() {
  jq -n \
    --arg dependency "${1:-quota-axi}" \
    --arg adopted "${2:-0.1.25}" \
    --arg required "${3:-0.1.25}" \
    --arg commit "${4:-$commit}" \
    '{
      schema_version: 1,
      exceptions: [{
        dependency: $dependency,
        previous_version: "0.1.18",
        adopted_version: $adopted,
        required_version: $required,
        firstmate_repository: "kunchenguid/firstmate",
        firstmate_commit: $commit
      }]
    }' >"$tmp_dir/repo/exceptions.json"
}

run_checker() {
  DOTFILES_DIR="$tmp_dir/repo" \
    FIRSTMATE_FLOOR_REGISTRY="$tmp_dir/repo/floors.tsv" \
    FIRSTMATE_FLOOR_EXCEPTIONS_FILE="$tmp_dir/repo/exceptions.json" \
    GH_AXI_BIN="$tmp_dir/bin/gh-axi" \
    NPM_BIN="$tmp_dir/bin/npm" \
    TOOL_UPDATE_NOW_EPOCH="$now_epoch" \
    TOOL_UPDATE_COOLDOWN_DAYS=7 \
    FIXTURE_COMMIT="$commit" \
    FIXTURE_FRESH_AT="$fresh_at" \
    FIXTURE_OLD_AT="$old_at" \
    "$CHECKER"
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

write_exception quota-axi 0.1.26 0.1.25
jq '.dependencies["quota-axi"] = "0.1.26"' "$tmp_dir/repo/agent-tools/package.json" \
  >"$tmp_dir/repo/agent-tools/package.json.next"
mv "$tmp_dir/repo/agent-tools/package.json.next" "$tmp_dir/repo/agent-tools/package.json"
expect_failure 'is broader than the lowest released version 0.1.25'

write_exception treehouse 2.1.2 2.1.2
expect_failure 'does not name a supported Firstmate dependency floor'

write_exception quota-axi 0.1.24 0.1.25
jq '.dependencies["quota-axi"] = "0.1.24"' "$tmp_dir/repo/agent-tools/package.json" \
  >"$tmp_dir/repo/agent-tools/package.json.next"
mv "$tmp_dir/repo/agent-tools/package.json.next" "$tmp_dir/repo/agent-tools/package.json"
expect_failure 'does not satisfy required version 0.1.25'

write_exception quota-axi 0.1.25 0.1.24
jq '.dependencies["quota-axi"] = "0.1.25"' "$tmp_dir/repo/agent-tools/package.json" \
  >"$tmp_dir/repo/agent-tools/package.json.next"
mv "$tmp_dir/repo/agent-tools/package.json.next" "$tmp_dir/repo/agent-tools/package.json"
expect_failure 'declares quota-axi floor 0.1.25, not recorded required version 0.1.24'

write_exception quota-axi 0.1.25 0.1.25 1111111111111111111111111111111111111111
expect_failure 'could not read Firstmate floor evidence'

printf '{"dependencies":{"quota-axi":"0.1.24"}}\n' >"$tmp_dir/repo/agent-tools/package.json"
if DOTFILES_DIR="$tmp_dir/repo" \
  FIRSTMATE_FLOOR_REGISTRY="$tmp_dir/repo/floors.tsv" \
  GH_AXI_BIN="$tmp_dir/bin/gh-axi" \
  FIXTURE_COMMIT="$commit" \
  "$CHECKER" --candidate "$commit" >"$tmp_dir/output" 2>&1; then
  fail 'candidate preflight accepted an unmet quota-axi floor'
fi
grep -Fq 'unmet: quota-axi pin 0.1.24 is below Firstmate floor 0.1.25' "$tmp_dir/output" || {
  cat "$tmp_dir/output" >&2
  fail 'candidate preflight did not report the unmet floor'
}

printf '%s\n' 'Firstmate floor exception checks passed'
