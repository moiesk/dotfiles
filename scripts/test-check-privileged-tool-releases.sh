#!/usr/bin/env bash
# Fixture for scripts/check-privileged-tool-releases.sh.
#
# Scenario under test: a freshly published npm "latest" must not hide an older
# release that has already cleared the cooldown. Every version and timestamp
# below is derived at run time from the live pins and from the checker's own
# cooldown, so a routine pin bump cannot quietly turn the scenario into a
# no-op the way a hardcoded fixture did (issue #61). The fixture_error guards
# fail loudly, naming this file, whenever the derivation stops producing the
# condition under test.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIXTURE_NAME="$(basename "${BASH_SOURCE[0]}")"
CHECKER="$DOTFILES_DIR/scripts/check-privileged-tool-releases.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture_error() {
  printf 'error: the fixture in scripts/%s is degenerate: %s\n' "$FIXTURE_NAME" "$1" >&2
  printf '%s\n' \
    'the scenario under test was never constructed, so this says nothing about' \
    'scripts/check-privileged-tool-releases.sh; repair the fixture instead' >&2
  exit 1
}

epoch_to_iso() {
  date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null ||
    date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ'
}

iso_to_epoch() {
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" '+%s' 2>/dev/null ||
    date -u -d "$1" '+%s'
}

version_gt() {
  local -a left right
  IFS=. read -r -a left <<<"$1"
  IFS=. read -r -a right <<<"$2"
  if ((left[0] != right[0])); then
    if ((left[0] > right[0])); then return 0; fi
    return 1
  fi
  if ((left[1] != right[1])); then
    if ((left[1] > right[1])); then return 0; fi
    return 1
  fi
  if ((left[2] > right[2])); then return 0; fi
  return 1
}

# Age the synthetic releases against the cooldown the checker will actually
# apply rather than restating it here, so the two cannot drift apart.
cooldown_days="$(sed -n \
  's/^COOLDOWN_DAYS="\${TOOL_UPDATE_COOLDOWN_DAYS:-\([0-9]\{1,\}\)}"$/\1/p' \
  "$CHECKER")"
[[ "$cooldown_days" =~ ^[0-9]+$ ]] ||
  fixture_error 'the default cooldown could not be read from the release check'
((cooldown_days > 0)) ||
  fixture_error "the release check defaults to a ${cooldown_days}-day cooldown, so no release can be held"

# A frozen clock keeps the run deterministic; every timestamp is an offset from it.
now_epoch="$(iso_to_epoch '2026-08-01T00:00:00Z')"
cutoff_epoch=$((now_epoch - cooldown_days * 86400))
pinned_published_epoch=$((cutoff_epoch - 30 * 86400))
intermediate_published_epoch=$((cutoff_epoch - 2 * 86400))
latest_published_epoch=$((now_epoch - 43200))

# Tier B stubs are incidental scaffolding: report each flake-pinned tool as
# already on its pinned release so the only checker failure is the one under test.
FIXTURE_TREEHOUSE_TAG="$(jq -er '.nodes.treehouse.original.ref' "$DOTFILES_DIR/flake.lock")" ||
  fixture_error 'flake.lock has no treehouse ref to mirror'
FIXTURE_NO_MISTAKES_TAG="$(jq -er '.nodes["no-mistakes"].original.ref' "$DOTFILES_DIR/flake.lock")" ||
  fixture_error 'flake.lock has no no-mistakes ref to mirror'
FIXTURE_GITHUB_PUBLISHED_AT="$(epoch_to_iso "$pinned_published_epoch")"

# Tier A: build the release under test one patch above the live pin, and a
# fresh latest one patch above that.
FIXTURE_NPM_PACKAGE='quota-axi'
FIXTURE_NPM_PINNED="$(jq -er --arg package "$FIXTURE_NPM_PACKAGE" \
  '.dependencies[$package]' "$DOTFILES_DIR/agent-tools/package.json")" ||
  fixture_error "agent-tools/package.json has no $FIXTURE_NPM_PACKAGE pin to build on"
[[ "$FIXTURE_NPM_PINNED" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] ||
  fixture_error "the $FIXTURE_NPM_PACKAGE pin ($FIXTURE_NPM_PINNED) is not a plain major.minor.patch version"
FIXTURE_NPM_INTERMEDIATE="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"
FIXTURE_NPM_LATEST="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 2))"
history_revision="$(git -C "$DOTFILES_DIR" rev-parse --verify HEAD)"
FIXTURE_NPM_PREVIOUS=''
while [[ -n "$history_revision" ]]; do
  history_pin="$(git -C "$DOTFILES_DIR" show "$history_revision:agent-tools/package.json" |
    jq -er --arg package "$FIXTURE_NPM_PACKAGE" '.dependencies[$package]')" ||
    fixture_error "could not derive historical $FIXTURE_NPM_PACKAGE pin"
  if [[ "$history_pin" != "$FIXTURE_NPM_PINNED" ]]; then
    FIXTURE_NPM_PREVIOUS="$history_pin"
    break
  fi
  history_revision="$(git -C "$DOTFILES_DIR" rev-parse --verify "$history_revision^" 2>/dev/null || true)"
done
[[ "$FIXTURE_NPM_PREVIOUS" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  fixture_error "no historical pin preceding $FIXTURE_NPM_PACKAGE $FIXTURE_NPM_PINNED was found"
FIXTURE_NPM_PINNED_AT="$(epoch_to_iso "$pinned_published_epoch")"
FIXTURE_NPM_INTERMEDIATE_AT="$(epoch_to_iso "$intermediate_published_epoch")"
FIXTURE_NPM_LATEST_AT="$(epoch_to_iso "$latest_published_epoch")"
FIXTURE_FIRSTMATE_COMMIT='0000000000000000000000000000000000000000'

version_gt "$FIXTURE_NPM_INTERMEDIATE" "$FIXTURE_NPM_PINNED" ||
  fixture_error "the release under test ($FIXTURE_NPM_INTERMEDIATE) does not sit above the $FIXTURE_NPM_PACKAGE pin ($FIXTURE_NPM_PINNED), so there is nothing for the check to flag"
version_gt "$FIXTURE_NPM_LATEST" "$FIXTURE_NPM_INTERMEDIATE" ||
  fixture_error "the latest release ($FIXTURE_NPM_LATEST) does not sit above the release under test ($FIXTURE_NPM_INTERMEDIATE), so it cannot hide it"
((intermediate_published_epoch <= cutoff_epoch)) ||
  fixture_error "$FIXTURE_NPM_INTERMEDIATE is published inside the ${cooldown_days}-day cooldown, so no eligible release is being hidden"
((latest_published_epoch > cutoff_epoch && latest_published_epoch <= now_epoch)) ||
  fixture_error "$FIXTURE_NPM_LATEST is not published inside the ${cooldown_days}-day cooldown, so it is not the fresh latest the scenario needs"

cat >"$tmp_dir/gh-axi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"/repos/kunchenguid/firstmate/contents/bin/fm-quota-axi-lib.sh?ref=$FIXTURE_FIRSTMATE_COMMIT"*)
    printf 'api_response:\n  body: %s\n  truncated: false\n' "$FIXTURE_NPM_PINNED"
    exit 0
    ;;
  *treehouse*) tag="$FIXTURE_TREEHOUSE_TAG" ;;
  *no-mistakes*) tag="$FIXTURE_NO_MISTAKES_TAG" ;;
  *) exit 1 ;;
esac
printf 'tag_name: %s\npublished_at: "%s"\n' "$tag" "$FIXTURE_GITHUB_PUBLISHED_AT"
EOF

cat >"$tmp_dir/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
package="$2"
pinned="$(jq -r --arg package "$package" \
  '.dependencies[$package]' "$DOTFILES_DIR/agent-tools/package.json")"
if [[ "${FIXTURE_MODE:-}" == malformed-pinned && "$package" == "$FIXTURE_NPM_PACKAGE" ]]; then
  jq -n --arg pinned "$pinned" \
    '{
      "dist-tags": {latest: $pinned},
      versions: [$pinned],
      time: {($pinned): "not-a-timestamp"}
    }'
elif [[ "${FIXTURE_MODE:-}" == fresh-available && "$package" == "$FIXTURE_NPM_PACKAGE" ]]; then
  jq -n \
    --arg pinned "$pinned" \
    --arg latest "$FIXTURE_NPM_LATEST" \
    --arg pinned_at "$FIXTURE_NPM_PINNED_AT" \
    --arg latest_at "$FIXTURE_NPM_LATEST_AT" \
    '{
      "dist-tags": {latest: $latest},
      versions: [$pinned, $latest],
      time: {($pinned): $pinned_at, ($latest): $latest_at}
    }'
elif [[ "${FIXTURE_MODE:-}" == pinned-latest && "$package" == "$FIXTURE_NPM_PACKAGE" ]]; then
  jq -n --arg pinned "$pinned" --arg published "$FIXTURE_NPM_LATEST_AT" \
    '{
      "dist-tags": {latest: $pinned},
      versions: [$pinned],
      time: {($pinned): $published}
    }'
elif [[ "$package" == "$FIXTURE_NPM_PACKAGE" ]]; then
  jq -n \
    --arg pinned "$pinned" \
    --arg intermediate "$FIXTURE_NPM_INTERMEDIATE" \
    --arg latest "$FIXTURE_NPM_LATEST" \
    --arg pinned_at "$FIXTURE_NPM_PINNED_AT" \
    --arg intermediate_at "$FIXTURE_NPM_INTERMEDIATE_AT" \
    --arg latest_at "$FIXTURE_NPM_LATEST_AT" \
    '{
      "dist-tags": {latest: $latest},
      versions: [$pinned, $intermediate, $latest],
      time: {
        ($pinned): $pinned_at,
        ($intermediate): $intermediate_at,
        ($latest): $latest_at
      }
    }'
else
  jq -n --arg pinned "$pinned" --arg pinned_at "$FIXTURE_NPM_PINNED_AT" \
    '{
      "dist-tags": {latest: $pinned},
      versions: [$pinned],
      time: {($pinned): $pinned_at}
    }'
fi
EOF
chmod +x "$tmp_dir/gh-axi" "$tmp_dir/npm"
printf '{"schema_version":1,"exceptions":[]}\n' >"$tmp_dir/exceptions.json"

export DOTFILES_DIR
export FIXTURE_TREEHOUSE_TAG FIXTURE_NO_MISTAKES_TAG FIXTURE_GITHUB_PUBLISHED_AT
export FIXTURE_NPM_PACKAGE FIXTURE_NPM_INTERMEDIATE FIXTURE_NPM_LATEST
export FIXTURE_NPM_PINNED_AT FIXTURE_NPM_INTERMEDIATE_AT FIXTURE_NPM_LATEST_AT
export FIXTURE_NPM_PINNED
export FIXTURE_NPM_PREVIOUS
export FIXTURE_FIRSTMATE_COMMIT

output_file="$tmp_dir/output"
if GH_AXI_BIN="$tmp_dir/gh-axi" \
  NPM_BIN="$tmp_dir/npm" \
  FIRSTMATE_FLOOR_EXCEPTIONS_FILE="$tmp_dir/exceptions.json" \
  TOOL_UPDATE_NOW_EPOCH="$now_epoch" \
  TOOL_UPDATE_COOLDOWN_DAYS="$cooldown_days" \
  "$CHECKER" >"$output_file" 2>&1; then
  cat "$output_file" >&2
  printf 'error: an eligible intermediate npm release was hidden by a fresh latest release (%s %s past cooldown behind %s, pinned %s)\n' \
    "$FIXTURE_NPM_PACKAGE" "$FIXTURE_NPM_INTERMEDIATE" "$FIXTURE_NPM_LATEST" \
    "$FIXTURE_NPM_PINNED" >&2
  exit 1
fi

expected_error="error: $FIXTURE_NPM_PACKAGE stable release $FIXTURE_NPM_INTERMEDIATE is past cooldown; pinned release is $FIXTURE_NPM_PINNED"
if ! grep -Fq "$expected_error" "$output_file"; then
  cat "$output_file" >&2
  printf 'error: the release check did not report the highest eligible npm release\nexpected: %s\n' \
    "$expected_error" >&2
  exit 1
fi

# Only the release under test may fail; anything else means the incidental
# stubs above no longer mirror the live pins.
reported_errors="$(grep -c '^error: ' "$output_file" || true)"
((reported_errors == 1)) ||
  fixture_error "the stubbed tools produced $reported_errors checker errors, but only $FIXTURE_NPM_PACKAGE is under test"

# A pin moved to a release that is still inside cooldown is itself a policy
# violation. In particular, pinned == latest must not make that adoption pass.
if FIXTURE_MODE=pinned-latest \
  GH_AXI_BIN="$tmp_dir/gh-axi" \
  NPM_BIN="$tmp_dir/npm" \
  FIRSTMATE_FLOOR_EXCEPTIONS_FILE="$tmp_dir/exceptions.json" \
  TOOL_UPDATE_NOW_EPOCH="$now_epoch" \
  TOOL_UPDATE_COOLDOWN_DAYS="$cooldown_days" \
  "$CHECKER" >"$output_file" 2>&1; then
  cat "$output_file" >&2
  printf '%s\n' 'error: a fresh npm release passed merely because pinned == latest' >&2
  exit 1
fi
expected_error="error: $FIXTURE_NPM_PACKAGE pinned release $FIXTURE_NPM_PINNED is still in the ${cooldown_days}-day cooldown without a valid Firstmate floor exception"
grep -Fq "$expected_error" "$output_file" || {
  cat "$output_file" >&2
  printf 'error: the pinned-equals-latest bypass was not rejected\nexpected: %s\n' \
    "$expected_error" >&2
  exit 1
}

if FIXTURE_MODE=malformed-pinned \
  GH_AXI_BIN="$tmp_dir/gh-axi" \
  NPM_BIN="$tmp_dir/npm" \
  FIRSTMATE_FLOOR_EXCEPTIONS_FILE="$tmp_dir/exceptions.json" \
  TOOL_UPDATE_NOW_EPOCH="$now_epoch" \
  TOOL_UPDATE_COOLDOWN_DAYS="$cooldown_days" \
  "$CHECKER" >"$output_file" 2>&1; then
  cat "$output_file" >&2
  printf '%s\n' 'error: malformed pinned release metadata passed the cooldown gate' >&2
  exit 1
fi
expected_error="error: $FIXTURE_NPM_PACKAGE pinned release $FIXTURE_NPM_PINNED has a malformed publication timestamp"
grep -Fq "$expected_error" "$output_file" || {
  cat "$output_file" >&2
  printf 'error: malformed pinned release timestamp was not rejected\nexpected: %s\n' \
    "$expected_error" >&2
  exit 1
}

# Normal policy remains a hold, not an error: an old committed pin is accepted
# while the only newer stable release is still inside cooldown.
if ! FIXTURE_MODE=fresh-available \
  GH_AXI_BIN="$tmp_dir/gh-axi" \
  NPM_BIN="$tmp_dir/npm" \
  FIRSTMATE_FLOOR_EXCEPTIONS_FILE="$tmp_dir/exceptions.json" \
  TOOL_UPDATE_NOW_EPOCH="$now_epoch" \
  TOOL_UPDATE_COOLDOWN_DAYS="$cooldown_days" \
  "$CHECKER" >"$output_file" 2>&1; then
  cat "$output_file" >&2
  printf '%s\n' 'error: normal cooldown rejected an old pin while only a fresh release was available' >&2
  exit 1
fi
grep -Fq "$FIXTURE_NPM_PACKAGE $FIXTURE_NPM_LATEST is available but remains in the ${cooldown_days}-day cooldown (pinned: $FIXTURE_NPM_PINNED)" \
  "$output_file" || {
  cat "$output_file" >&2
  printf '%s\n' 'error: normal cooldown did not report the held fresh release' >&2
  exit 1
}

# The same fresh pinned release is allowed only when exact Firstmate commit
# evidence declares that floor and the pin is the lowest satisfying release.
FIXTURE_FIRSTMATE_COMMIT='2222222222222222222222222222222222222222'
export FIXTURE_FIRSTMATE_COMMIT
jq -n \
  --arg version "$FIXTURE_NPM_PINNED" \
  --arg commit "$FIXTURE_FIRSTMATE_COMMIT" \
  --arg previous "$FIXTURE_NPM_PREVIOUS" \
  '{
    schema_version: 1,
    exceptions: [{
      dependency: "quota-axi",
      previous_version: $previous,
      adopted_version: $version,
      required_version: $version,
      firstmate_repository: "kunchenguid/firstmate",
      firstmate_commit: $commit
    }]
  }' >"$tmp_dir/exceptions.json"
if ! FIXTURE_MODE=pinned-latest \
  GH_AXI_BIN="$tmp_dir/gh-axi" \
  NPM_BIN="$tmp_dir/npm" \
  FIRSTMATE_FLOOR_EXCEPTIONS_FILE="$tmp_dir/exceptions.json" \
  TOOL_UPDATE_NOW_EPOCH="$now_epoch" \
  TOOL_UPDATE_COOLDOWN_DAYS="$cooldown_days" \
  "$CHECKER" >"$output_file" 2>&1; then
  cat "$output_file" >&2
  printf '%s\n' 'error: a valid Firstmate floor exception did not authorize the fresh pin' >&2
  exit 1
fi
grep -Fq "$FIXTURE_NPM_PACKAGE pinned release $FIXTURE_NPM_PINNED is inside cooldown under a valid Firstmate floor exception" \
  "$output_file" || {
  cat "$output_file" >&2
  printf '%s\n' 'error: the checker did not report its valid Firstmate floor exception' >&2
  exit 1
}

if [[ "$(grep -c '^[[:space:]]*interval: daily$' "$DOTFILES_DIR/.github/dependabot.yml")" -ne 2 ]]; then
  printf '%s\n' 'error: npm Dependabot checks must run daily so updates are proposed when cooldown expires' >&2
  exit 1
fi

printf '%s\n' 'privileged tool release check tests passed'
