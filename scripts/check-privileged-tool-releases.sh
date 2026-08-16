#!/usr/bin/env bash
# Report stable privileged-tool releases after the routine cooldown.
# Tier B (treehouse, no-mistakes) is pinned in flake.lock; Tier A (gh-axi,
# chrome-devtools-axi, quota-axi) is pinned in agent-tools/package.json. Both
# tiers get the same hold: a release past cooldown fails until the pin moves.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
GH_AXI_BIN="${GH_AXI_BIN:-gh-axi}"
NPM_BIN="${NPM_BIN:-npm}"
COOLDOWN_DAYS="${TOOL_UPDATE_COOLDOWN_DAYS:-7}"
NOW_EPOCH="${TOOL_UPDATE_NOW_EPOCH:-$(date -u +%s)}"
EXCEPTIONS_FILE="${FIRSTMATE_FLOOR_EXCEPTIONS_FILE:-$DOTFILES_DIR/security/firstmate-floor-exceptions.json}"
FAILURES=0

"$DOTFILES_DIR/scripts/check-firstmate-floor-exceptions.sh"

has_floor_exception() {
  local dependency="$1" pinned="$2"
  jq -e --arg dependency "$dependency" --arg pinned "$pinned" '
    any(.exceptions[];
      .dependency == $dependency and .adopted_version == $pinned)
  ' "$EXCEPTIONS_FILE" >/dev/null
}

check_release() {
  local input_name="$1" repository="$2"
  local pinned metadata latest published published_epoch now age_seconds cooldown_seconds
  local pinned_metadata pinned_published pinned_published_epoch pinned_age_seconds

  if ! pinned="$(jq -er --arg input "$input_name" \
    '.nodes[$input].original.ref' "$DOTFILES_DIR/flake.lock")"; then
    printf 'error: could not read pinned release for %s from flake.lock\n' "$input_name" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  if ! metadata="$("$GH_AXI_BIN" api GET "/repos/$repository/releases/latest")"; then
    printf 'error: could not fetch latest release metadata for %s with %s\n' \
      "$repository" "$GH_AXI_BIN" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  latest="$(awk -F': ' '/^tag_name:/ { print $2; exit }' <<<"$metadata")"
  published="$(awk -F': ' '/^published_at:/ { print $2; exit }' <<<"$metadata")"
  published="${published%\"}"
  published="${published#\"}"

  if [[ -z "$latest" || -z "$published" ]]; then
    printf 'error: incomplete release metadata for %s\n' "$repository" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  if [[ "$pinned" == "$latest" ]]; then
    pinned_published="$published"
  else
    if ! pinned_metadata="$($GH_AXI_BIN api GET "/repos/$repository/releases/tags/$pinned")"; then
      printf 'error: could not fetch pinned release metadata for %s with %s\n' \
        "$repository" "$GH_AXI_BIN" >&2
      FAILURES=$((FAILURES + 1))
      return
    fi
    pinned_published="$(awk -F': ' '/^published_at:/ { print $2; exit }' <<<"$pinned_metadata")"
    pinned_published="${pinned_published%\"}"
    pinned_published="${pinned_published#\"}"
  fi
  if [[ -z "$pinned_published" ]]; then
    printf 'error: incomplete pinned release metadata for %s %s\n' "$repository" "$pinned" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  pinned_published_epoch="$(node -e \
    'const value = Date.parse(process.argv[1]); if (!Number.isFinite(value)) process.exit(1); console.log(Math.floor(value / 1000));' \
    "$pinned_published")"
  pinned_age_seconds=$((NOW_EPOCH - pinned_published_epoch))
  cooldown_seconds=$((COOLDOWN_DAYS * 86400))
  if ((pinned_age_seconds < cooldown_seconds)); then
    if has_floor_exception "$input_name" "${pinned#v}"; then
      printf '%s pinned release %s is inside cooldown under a valid Firstmate floor exception\n' \
        "$input_name" "$pinned"
    else
      printf 'error: %s pinned release %s is still in the %s-day cooldown without a valid Firstmate floor exception\n' \
        "$input_name" "$pinned" "$COOLDOWN_DAYS" >&2
      FAILURES=$((FAILURES + 1))
      return
    fi
  fi

  if [[ "$pinned" == "$latest" ]]; then
    printf '%s is on the latest stable release (%s)\n' "$input_name" "$pinned"
    return
  fi

  published_epoch="$(node -e \
    'const value = Date.parse(process.argv[1]); if (!Number.isFinite(value)) process.exit(1); console.log(Math.floor(value / 1000));' \
    "$published")"
  now="$NOW_EPOCH"
  age_seconds=$((now - published_epoch))
  cooldown_seconds=$((COOLDOWN_DAYS * 86400))

  if ((age_seconds < cooldown_seconds)); then
    printf '%s %s is available but remains in the %s-day cooldown (pinned: %s)\n' \
      "$input_name" "$latest" "$COOLDOWN_DAYS" "$pinned"
    return
  fi

  printf 'error: %s stable release %s is past cooldown; pinned release is %s\n' \
    "$input_name" "$latest" "$pinned" >&2
  FAILURES=$((FAILURES + 1))
}

check_npm_release() {
  local package_name="$1"
  local pinned metadata latest published published_epoch now age_seconds cooldown_seconds eligible
  local pinned_published pinned_published_epoch pinned_age_seconds

  if ! pinned="$(jq -er --arg pkg "$package_name" \
    '.dependencies[$pkg]' "$DOTFILES_DIR/agent-tools/package.json")"; then
    printf 'error: could not read pinned version for %s from agent-tools/package.json\n' \
      "$package_name" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  if ! metadata="$("$NPM_BIN" view "$package_name" --json 2>/dev/null)"; then
    printf 'error: could not fetch npm metadata for %s with %s\n' \
      "$package_name" "$NPM_BIN" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  latest="$(jq -r '.["dist-tags"].latest // empty' <<<"$metadata")"
  published="$(jq -r --arg v "$latest" '.time[$v] // empty' <<<"$metadata")"

  if [[ -z "$latest" || -z "$published" ]]; then
    printf 'error: incomplete npm metadata for %s\n' "$package_name" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  pinned_published="$(jq -r --arg v "$pinned" '.time[$v] // empty' <<<"$metadata")"
  if [[ -z "$pinned_published" ]]; then
    printf 'error: npm metadata does not contain pinned release %s %s\n' "$package_name" "$pinned" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  pinned_published_epoch="$(node -e \
    'const value = Date.parse(process.argv[1]); if (!Number.isFinite(value)) process.exit(1); console.log(Math.floor(value / 1000));' \
    "$pinned_published")"
  pinned_age_seconds=$((NOW_EPOCH - pinned_published_epoch))
  cooldown_seconds=$((COOLDOWN_DAYS * 86400))
  if ((pinned_age_seconds < cooldown_seconds)); then
    if has_floor_exception "$package_name" "$pinned"; then
      printf '%s pinned release %s is inside cooldown under a valid Firstmate floor exception\n' \
        "$package_name" "$pinned"
    else
      printf 'error: %s pinned release %s is still in the %s-day cooldown without a valid Firstmate floor exception\n' \
        "$package_name" "$pinned" "$COOLDOWN_DAYS" >&2
      FAILURES=$((FAILURES + 1))
      return
    fi
  fi

  if [[ "$pinned" == "$latest" ]]; then
    printf '%s is on the latest stable release (%s)\n' "$package_name" "$pinned"
    return
  fi

  published_epoch="$(node -e \
    'const value = Date.parse(process.argv[1]); if (!Number.isFinite(value)) process.exit(1); console.log(Math.floor(value / 1000));' \
    "$published")"
  now="$NOW_EPOCH"
  age_seconds=$((now - published_epoch))
  cooldown_seconds=$((COOLDOWN_DAYS * 86400))

  # A newly published latest release must not hide an older release that has
  # already completed the cooldown. Select the highest stable eligible version.
  eligible="$(node -e '
    const metadata = JSON.parse(process.argv[1]);
    const pinned = process.argv[2].split(".").map(Number);
    const cutoff = Number(process.argv[3]) * 1000;
    const parse = value => /^\d+\.\d+\.\d+$/.test(value)
      ? value.split(".").map(Number)
      : null;
    const compare = (a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2];
    const candidates = (metadata.versions || [])
      .map(value => ({ value, parsed: parse(value), published: Date.parse(metadata.time?.[value]) }))
      .filter(item => item.parsed && Number.isFinite(item.published) && item.published <= cutoff)
      .sort((a, b) => compare(b.parsed, a.parsed));
    if (candidates[0] && compare(candidates[0].parsed, pinned) > 0) {
      process.stdout.write(candidates[0].value);
    }
  ' "$metadata" "$pinned" "$((now - cooldown_seconds))")"

  if [[ -n "$eligible" ]]; then
    printf 'error: %s stable release %s is past cooldown; pinned release is %s\n' \
      "$package_name" "$eligible" "$pinned" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  if ((age_seconds < cooldown_seconds)); then
    printf '%s %s is available but remains in the %s-day cooldown (pinned: %s)\n' \
      "$package_name" "$latest" "$COOLDOWN_DAYS" "$pinned"
    return
  fi

  printf 'error: %s stable release %s is past cooldown; pinned release is %s\n' \
    "$package_name" "$latest" "$pinned" >&2
  FAILURES=$((FAILURES + 1))
}

# Tier B: flake-pinned workflow tools.
check_release treehouse kunchenguid/treehouse
check_release no-mistakes kunchenguid/no-mistakes

# Tier A: npm-pinned privileged tools (agent-tools/package.json).
check_npm_release gh-axi
check_npm_release chrome-devtools-axi
check_npm_release quota-axi

if ((FAILURES > 0)); then
  exit 1
fi
